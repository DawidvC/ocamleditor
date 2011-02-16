(*

  OCamlEditor
  Copyright (C) 2010, 2011 Francesco Tovagliari

  This file is part of OCamlEditor.

  OCamlEditor is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  OCamlEditor is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program. If not, see <http://www.gnu.org/licenses/>.

*)

open Str
open GdkKeysyms
open Parser
open Miscellanea
open Printf


let re_trailng_blanks = Miscellanea.regexp "\\([ \t]+\\)\r?$"

let shells = ref []

let create_shell = ref ((fun () -> failwith "Ocaml_text.create_shell") : unit -> unit)
let show_messages = ref ((fun () -> failwith "Ocaml_text.show_messages") : unit -> unit)

(** Buffer *)
class buffer ?project ?file ?(lexical_enabled=false) () =
object (self)
  inherit Text.buffer ?file () as super
  val mutable lexical_enabled = (lexical_enabled || begin
    match file with
      | Some file when (file#name ^^ ".ml" || file#name ^^ ".mli" || file#name ^^ ".mll" || file#name ^^ ".mly") -> true
      | _ -> false
  end)
  val mutable shell : Shell.shell option = None
  val mutable select_word_state = []
  val mutable select_word_state_init = None
  val mutable changed_after_last_autocomp = 0.0

  method changed_after_last_autocomp = changed_after_last_autocomp
  method set_changed_after_last_autocomp x = changed_after_last_autocomp <- x

  method set_lexical_enabled x = lexical_enabled <- x
  method lexical_enabled = lexical_enabled

  method indent ?(dir=(`FORWARD : [`FORWARD | `BACKWARD])) ?start ?stop () =
    let old = lexical_enabled in
    self#set_lexical_enabled false;
    super#indent ~dir ?start ?stop ();
    self#set_lexical_enabled old;

  method trim_lines () =
    let nlines = self#line_count in
    let ins_line = (self#get_iter `INSERT)#line in
    for i = 0 to nlines - 1 do
      if i <> ins_line then begin
        let it = self#get_iter (`LINE i) in
        let line = self#get_line_at_iter it in
        try
          let _ = Str.search_forward re_trailng_blanks line 0 in
          let len = String.length (Str.matched_group 1 line) in
          let stop = it#forward_to_line_end in
          let start = stop#backward_chars len in
          self#delete ~start ~stop;
        with Not_found -> ();
      end
    done;

  method shell = match shell with None -> None
    | Some sh -> if not sh#alive then (shell <- None; shell) else shell

  method select_shell () =
    shell <- (match !shells with
      | [] -> None
      | [sh] -> Some sh
      | x -> Some (List.hd x));

  method send_to_shell () =
    let phrase = self#phrase_at_cursor () in
    match self#shell with
      | None ->
        self#select_shell ();
        if self#shell = None then begin
          !create_shell();
          self#select_shell ()
        end;
        self#send_to_shell ()
      | Some sh ->
        if String.length phrase > 0 then begin
          let phrase = if not (Str.string_match (Miscellanea.regexp ";;") phrase 0)
          then (phrase ^ ";;") else phrase in
          sh#send phrase;
          sh#send "\n";
        end

  method phrase_at_cursor () =
    let phrase = self#selection_text() in
    if String.length phrase > 0 then phrase else begin
      let text = self#get_text () in
      let buffer = Lexing.from_string text in
      let start = ref 0
      and block_start = ref []
      and pend = ref (-1)
      and after = ref false in
      while !pend = -1 do
        let token = Lexer.token buffer in
        let pos =
          if token = SEMISEMI then Lexing.lexeme_end buffer
          else Lexing.lexeme_start buffer
        in
        let bol = (pos = 0) || text.[pos-1] = '\n' in
        let it_pos = self#get_iter (`OFFSET pos) in
        let it_ins = self#get_iter `INSERT in
        if not !after && (it_pos#compare it_ins >= if bol then 1 else 0)
        then begin
          after := true;
          let anon, real = List.partition (fun x -> x = -1) !block_start in
          block_start := anon;
          if real <> [] then start := List.hd real;
        end;
        match token with
        | CLASS | EXTERNAL | EXCEPTION | FUNCTOR
        | LET | MODULE | OPEN | TYPE | VAL | SHARP when bol ->
          if !block_start = [] then
            if !after then pend := pos else start := pos
          else block_start := pos :: List.tl !block_start
        | SEMISEMI ->
          if !block_start = [] then
            if !after then pend := Lexing.lexeme_start buffer
            else start := pos
          else block_start := pos :: List.tl !block_start
        | BEGIN | OBJECT ->
          block_start := -1 :: !block_start
        | STRUCT | SIG ->
          block_start := Lexing.lexeme_end buffer :: !block_start
        | END ->
          if !block_start = [] then
            if !after then pend := pos else ()
          else block_start := List.tl !block_start
        | EOF ->
            pend := pos
        | _ -> ()
      done;
      let phrase = Miscellanea.trim (String.sub text !start (!pend - !start)) in
      phrase
    end

  method select_ocaml_word ?pat () =
    match pat with
      | Some pat -> super#select_word ~pat ()
      | None ->
        if self#has_selection then begin
          let selection = self#selection_text () in
          let start, stop = self#selection_bounds in
          let start, stop = if start#compare stop > 0 then stop, start else start, stop in
          if String.contains selection '_' then begin
            let parts = Miscellanea.split "_" selection in
            let start = ref start in
            select_word_state <- List.map begin fun p ->
              match !start#forward_search p with
                | None -> assert false
                | Some ((a, b) as bounds) ->
                  start := b;
                  bounds
            end parts;
            match select_word_state_init with
              | None -> ()
              | Some init ->
                select_word_state_init <- None;
                select_word_state <- List.filter (fun (_, b) -> init#compare b < 0) select_word_state;
          end;
          try
            select_word_state_init <- None;
            let a, b = List.hd select_word_state in
            self#select_range a b;
            select_word_state <- List.tl select_word_state;
            a, b
          with Failure "hd" -> begin
            self#place_cursor start;
            let bounds = self#select_ocaml_word ~pat:Ocaml_word_bound.regexp () in
            select_word_state_init <- None;
            bounds
          end
        end else begin
          select_word_state_init <- Some (self#get_iter `INSERT);
          let bounds = super#select_word ~pat:Ocaml_word_bound.regexp () in
          select_word_state <- [];
          bounds
        end

  method get_lident_at_cursor () =
    let stop = self#get_iter `INSERT in
    let start = (stop#backward_find_char begin fun c ->
      not (Glib.Unichar.isalnum c) &&
      let s = Glib.Utf8.from_unichar c in not (List.mem s ["."; "_"; "'"])
    end)#forward_char in
    let lident = Miscellanea.trim (self#get_text ~start ~stop ()) in
    let lident = Str.split_delim (Miscellanea.regexp "\\.") lident in
    let lident = if try List.hd lident = "" with _ -> false then List.tl lident else lident in
    lident

  method get_annot iter =
    if changed_after_last_autocomp = 0.0 then begin
      match file with
        | None -> None
        | Some file ->
          begin
            match project with
              | Some project ->
                begin
                  match project.Project.in_source_path file#path with
                    | Some filename ->
                      Annotation.find_block_at_offset ~filename ~offset:iter#offset
                        (*~offset:(Glib.Utf8.offset_to_pos (self#get_text ()) ~pos:0 ~off:iter#offset)*)
                    | _ -> None
                end;
              | _ -> None
          end;
    end else None

  initializer
    (** Lexical *)
    Lexical.init_tags (*?ocamldoc_paragraph_enabled*) (self :> GText.buffer);
    (** Lexical coloring disabled for undo of indent *)
    let old_lexical = ref lexical_enabled in
    undo#connect#undo ~callback:begin fun ~name ->
      if name = "indent" then (old_lexical := self#lexical_enabled; self#set_lexical_enabled false;);
    end;
    undo#connect#after#undo ~callback:begin fun ~name ->
      if name = "indent" then (self#set_lexical_enabled !old_lexical);
    end;
    undo#connect#redo ~callback:begin fun ~name ->
      if name = "indent" then (old_lexical := self#lexical_enabled; self#set_lexical_enabled false;);
    end;
    undo#connect#after#redo ~callback:begin fun ~name ->
      if name = "indent" then (self#set_lexical_enabled !old_lexical);
    end;
    ()

  method as_text_buffer = (self :> Text.buffer)
end

(** View *)
and view ?project ?buffer () =
  let buffer = match buffer with None -> new buffer ?project () | Some b -> b in
object (self)
  inherit Text.view ~buffer:buffer#as_text_buffer () as super
  val mutable popup = None
  val mutable smart_click = true;
  val mutable code_folding = None

  method obuffer = buffer

  method smart_click = smart_click
  method set_smart_click x = smart_click <- x

  method private comment_block =
    let bounds = "(*", "*)" in
    fun reverse ->
      let bounds, len = if reverse then (snd bounds, fst bounds), (-2) else bounds, 2 in
      let tb = self#buffer in
      let start = tb#get_iter `SEL_BOUND in
      let stop = tb#get_iter `INSERT in
      let s1 = tb#get_text ~start ~stop:(start#forward_chars len)  () in
      let s2 = tb#get_text ~start:(stop#backward_chars len) ~stop () in
      if (s1 = (fst bounds)) && (s2 = (snd bounds)) then begin
        tb#delete ~start:start ~stop:(start#forward_chars len);
        tb#delete
          ~start:((tb#get_iter `INSERT)#backward_chars len) ~stop:(tb#get_iter `INSERT);
      end else begin
        tb#insert ~iter:start (fst bounds);
        tb#insert ~iter:(tb#get_iter `INSERT) (snd bounds);
        if reverse then
          tb#move_mark `INSERT ~where:((tb#get_iter `INSERT)#backward_chars 2)
        else
          tb#move_mark `SEL_BOUND ~where:((tb#get_iter `SEL_BOUND)#backward_chars 2)
      end;
      let start, stop = tb#get_iter_at_mark `SEL_BOUND, tb#get_iter `INSERT in
      let start, stop = if reverse then stop, start else start, stop in
      let stop = stop#forward_lines 2 in
      Lexical.tag ~start ~stop self#buffer;

  method toggle_comment () =
    if buffer#lexical_enabled then begin
      let f () =
        let tb = self#buffer in
        let start = tb#get_iter_at_mark `SEL_BOUND in
        let stop = tb#get_iter `INSERT in
        let comp = start#compare stop in
        let pos = stop#offset in
        if self#buffer#get_text ~start ~stop () = " " then begin
          self#buffer#insert ~iter:(if comp > 0 then start else stop) " ";
          self#comment_block (comp > 0);
          self#buffer#move_mark `INSERT ~where:(self#buffer#get_iter_at_mark `SEL_BOUND);
          let where = self#buffer#get_iter_at_mark `INSERT in
          self#buffer#place_cursor ~where:(if comp > 0 then where#backward_chars 3 else where#forward_chars 3);
          false
        end else if buffer#get_text ~start ~stop () = "  " then begin
          self#comment_block (comp > 0);
          buffer#move_mark `INSERT ~where:(buffer#get_iter_at_mark `SEL_BOUND);
          let where = buffer#get_iter_at_mark `INSERT in
          buffer#place_cursor ~where:(if comp > 0 then where#backward_chars 4 else where#forward_chars 2);
          buffer#insert ~iter:(buffer#get_iter `INSERT) "*";
          buffer#place_cursor ~where:(buffer#get_iter `INSERT)#forward_char;
          false
        end else begin
          if comp <> 0 then begin
            self#comment_block (comp > 0);
            true
          end else begin
            match
              Comments.nearest (Comments.scan
                (Glib.Convert.convert_with_fallback ~fallback:"?"
                  ~from_codeset:"utf8" ~to_codeset:Oe_config.ocaml_codeset (tb#get_text ()))) pos
            with
              | None -> false
              | Some (b, e) ->
                let i, s = if abs(pos - b) <= abs(pos - e) then b, e else e, b in
                tb#select_range (tb#get_iter_at_char s) (tb#get_iter_at_char i);
                self#scroll_lazy (tb#get_iter `INSERT);
                false
          end
        end;
      in
      buffer#undo#func f ~inverse:f;
      self#misc#grab_focus();
    end

  method get_annot_at_location ~x ~y =
    if self#misc#get_flag `HAS_FOCUS && ((*not*) buffer#changed_after_last_autocomp = 0.0) then begin
      let iter =
        let iter = self#get_iter_at_location ~x ~y in
        if iter#ends_line
        || Glib.Unichar.isspace iter#char
        || begin
          match Comments.enclosing
            (Comments.scan (Glib.Convert.convert_with_fallback ~fallback:"" ~from_codeset:"utf8" ~to_codeset:Oe_config.ocaml_codeset
              (self#buffer#get_text ()))) iter#offset
          with None -> false | _ -> true;
        end
        then None else (Some iter)
      in
      match iter with None -> None | Some iter -> buffer#get_annot iter
    end else None

  method completion () =
    if buffer#lexical_enabled then
      try
        let it = self#buffer#get_iter `INSERT in
        (* Quando disabilitare il popup *)
        (* 1. Nei commenti *)
        begin match Comments.enclosing
          (Comments.scan (Glib.Convert.convert_with_fallback ~fallback:"" ~from_codeset:"utf8" ~to_codeset:Oe_config.ocaml_codeset
            (buffer#get_text ()))) it#offset
        with None -> () | Some _ -> raise Not_found;
        end;
        (* 2. Nelle stringhe *)
        if Lex.in_string (buffer#get_text ()) it#offset then raise Not_found;
        let lident = buffer#get_lident_at_cursor () in
        let paths_opened = Lex.paths_opened (buffer#get_text ()) in
        let create_popup =
          if List.length lident = 1 then begin
            Completion.uident_lookup ~paths_opened
          end else if List.length lident = 2 then begin
            Completion.dot_lookup ~modlid:(List.hd lident)
          end else if List.length lident >= 3 then begin
            Completion.uident_lookup ~paths_opened
          end else
            Completion.uident_lookup ~paths_opened
         in
        (* Callback per il popup: get_word restituisce la stringa usata dal popup
          per posizionarsi sulla riga; on_type è la funzione usata dal popup per inserire
          stringhe nel testo; on_row_activated è l'azione da fare quando si conferma una riga
          del popup.
        *)
        let get_word () =
          let start, stop = buffer#select_word ~pat:Ocaml_word_bound.regexp ~select:false  ~limit:['.'] () in
          buffer#get_text ~start ~stop:(self#buffer#get_iter `INSERT) () in
        let on_type txt = if self#editable then (self#buffer#insert ~iter:(self#buffer#get_iter `INSERT) txt) in
        let on_row_activated txt =
          if self#editable then begin
            buffer#select_word ~pat:Ocaml_word_bound.regexp ~limit:['.'] ();
            buffer#delete_selection ();
            buffer#insert ~iter:(self#buffer#get_iter `INSERT) txt
          end
        in
        let p = create_popup ~on_row_activated ~on_type ~on_search:get_word in
        p#misc#connect#destroy ~callback:self#misc#grab_focus;
        (* Aggiornare il testo mentre si digita *)
        ignore (p#event#connect#key_press ~callback:begin fun ev ->
          let state = GdkEvent.Key.state ev and key = GdkEvent.Key.keyval ev in
          let ins = buffer#get_iter `INSERT in
          if key = _BackSpace then begin
            buffer#delete ~start:ins ~stop:ins#backward_char;
            p#search (get_word())
          end else if key = _Delete then begin
            buffer#delete ~start:ins ~stop:ins#forward_char;
          end else if GdkEvent.Key.string ev = "." then begin
            p#activate();
            if self#editable then (buffer#insert ~iter:(buffer#get_iter `INSERT) (GdkEvent.Key.string ev))
          end else if (state = [] || state = [`SHIFT]) && not (List.mem key [
              _Return;
              _Up;
              _Down;
              _Page_Up;
              _Page_Down;
              _End;
              _Home;
              _Escape
            ]) then (if self#editable then (buffer#insert ~iter:ins (GdkEvent.Key.string ev)));
          false
        end);
        ignore (self#scroll_to_iter it);
        let x, y = self#get_location_at_cursor () in
        p#move ~x ~y;
        Gaux.may (GWindow.toplevel self) ~f:(fun parent -> p#window#set_transient_for parent#as_window);
        p#window#set_opacity 0.0;
        p#present();
        let alloc = p#misc#allocation in
        let x, y =
          (if x + alloc.Gtk.width > (Gdk.Screen.width()) then (Gdk.Screen.width() - alloc.Gtk.width) else x),
          (if y + alloc.Gtk.height > (Gdk.Screen.height()) then (Gdk.Screen.height() - alloc.Gtk.height) else y);
        in
        p#move ~x ~y;
        Gtk_util.fade_window p#window;
      with Not_found -> ();

  method code_folding = match code_folding with Some m -> m | _ -> assert false

  method scroll_lazy iter =
    super#scroll_lazy iter;
    if (self#code_folding#is_folded iter) <> None then begin
      self#code_folding#expand iter;
    end;

  method align_definitions () =
    buffer#undo#begin_block ~name:"dot_leaders";
    Alignment.align_selection self#as_tview;
    buffer#undo#end_block();

  initializer
    code_folding <- Some (new Code_folding.manager ~view:(self :> Text.view));
    self#create_highlight_current_line_tag(); (* recreate current line tag after code folding highlight to draw it above *)
    ignore (self#event#connect#button_press ~callback:begin fun ev ->
      if smart_click then begin
        (** Double-click selects OCaml identifiers; click on a selected range
          reduces the selection to part of the identifier. *)
        match GdkEvent.get_type ev with
          | `TWO_BUTTON_PRESS ->
              ignore (self#obuffer#select_word ~pat:Ocaml_word_bound.regexp ());
              true (* true *)
          | `BUTTON_PRESS when buffer#has_selection ->
            let x = int_of_float (GdkEvent.Button.x ev) in
            let y = int_of_float (GdkEvent.Button.y ev) in
            let x, y = self#window_to_buffer_coords ~tag:`TEXT ~x ~y in
            let where = self#get_iter_at_location ~x ~y in
            let start, stop = buffer#selection_bounds in
            let start, stop = if start#compare stop > 0 then stop, start else start, stop in
            if where#in_range ~start ~stop then begin
              buffer#place_cursor ~where;
              let a, b = self#obuffer#select_word ~pat:Ocaml_word_bound.part () in
              if a#equal start && b#equal stop then begin
                buffer#place_cursor ~where;
                false
              end else true; (* true *)
            end else false;
          | _ -> false
      end else false
    end);
    (** Keypress *)
    ignore (self#event#connect#key_press ~callback:
      begin fun ev ->
        let key = GdkEvent.Key.keyval ev in
        let state = GdkEvent.Key.state ev in
        if state = [`MOD2] && key = _igrave then begin
          buffer#delete ~start:(self#buffer#get_iter `INSERT) ~stop:(self#buffer#get_iter `SEL_BOUND);
          buffer#insert "~";
          true
        end else if state = [`MOD2] && key = _apostrophe then begin
          buffer#delete ~start:(self#buffer#get_iter `INSERT) ~stop:(self#buffer#get_iter `SEL_BOUND);
          buffer#insert "`";
          true
        end else false;
      end);
    ()
end