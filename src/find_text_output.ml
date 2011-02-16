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

open Printf
open GdkKeysyms
open GUtil
open Gobject
open Find_text

let (//) = Filename.concat
let (^^) = Filename.check_suffix

let strip_cr =
  let re = Str.regexp "\r$" in
  fun line -> Str.replace_first re "" line

let new_mark_name = let i = ref 0 in fun () -> incr i; sprintf "find_text_%d" !i

(** widget *)
class widget
    ~(dialog : GWindow.window)
    ~(editor : Editor.editor)
    ?(buffer : GText.buffer option)
    ?packing () =
  let search_started = new search_started () in
  let search_finished = new search_finished () in
  let editor_buffer = buffer in
  let vbox = GPack.vbox ?packing () in
  let paned = GPack.paned `HORIZONTAL ~packing:vbox#add () in
  let toolbar = GButton.toolbar ~style:`ICONS ~orientation:`HORIZONTAL ~packing:vbox#pack () in
  let _ = toolbar#set_icon_size `MENU in
  let button_stop = GButton.tool_button ~stock:`STOP ~packing:toolbar#insert () in
  let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
  let button_prev_file = GButton.tool_button ~stock:`MEDIA_REWIND ~packing:toolbar#insert () in
  let button_prev_line = GButton.tool_button ~stock:`MEDIA_PREVIOUS ~packing:toolbar#insert () in
  let button_next_line = GButton.tool_button ~stock:`MEDIA_NEXT ~packing:toolbar#insert () in
  let button_next_file = GButton.tool_button ~stock:`MEDIA_FORWARD ~packing:toolbar#insert () in
  let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
  let button_remove = GButton.tool_button ~stock:`REMOVE ~packing:toolbar#insert () in
  let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
  let button_restart = GButton.tool_button ~stock:`REFRESH ~packing:toolbar#insert () in
  let button_new_search = GButton.tool_button ~stock:`FIND ~packing:toolbar#insert () in
  let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
  let item_message = GButton.tool_item ~packing:toolbar#insert () in
  let label_message = GMisc.label ~packing:item_message#add () in
  (*  *) 
  let lsw = GBin.scrolled_window ~shadow_type:`IN ~hpolicy:`NEVER ~vpolicy:`AUTOMATIC
    ~packing:(paned#pack1 ~resize:true ~shrink:true) () in
  let rsw = GBin.scrolled_window ~shadow_type:`IN ~hpolicy:`AUTOMATIC ~vpolicy:`AUTOMATIC
    ~packing:(paned#pack2 ~resize:true ~shrink:true) () in
  let tbuf = new Ocaml_text.buffer () in
  let preview = new Ocaml_text.view ~buffer:tbuf () in
  let _ = Preferences_apply.apply (preview :> Text.view) !Preferences.preferences in
  let _ = rsw#add preview#coerce in
  let _ = paned#set_position 420 in
  let _ = tbuf#create_tag ~name:"find_text_result_line" [] in
  (*  *) 
  let cols = new GTree.column_list in
  let col_file  = cols#add Gobject.Data.string in
  let col_hits  = cols#add Gobject.Data.int in
  let col_path  = cols#add Gobject.Data.string in
  let model = GTree.list_store cols in
  let view = GTree.view ~model:model ~headers_clickable:true ~packing:lsw#add () in
  let _ = view#misc#set_property "enable-grid-lines" (`INT 3) in
  let renderer = GTree.cell_renderer_text [] in
  let vc_file = GTree.view_column ~title:"File" ~renderer:(renderer, ["text", col_file]) () in
  let vc_hits = GTree.view_column ~title:"Hits" ~renderer:(renderer, ["text", col_hits]) () in
  let vc_path = GTree.view_column ~title:"Directory" ~renderer:(renderer, ["text", col_path]) () in
  let _ = vc_file#set_resizable true in
  let _ = vc_hits#set_resizable true in
  let _ = vc_path#set_resizable true in
object (self)
  inherit GObj.widget vbox#as_widget
  val mutable options = None
  val project = editor#project
  (*  *)
  val mutable sigids = []
  val mutable delete_marks = []
  val mutable selected_text_bounds = None
  val mutable canceled = false
  val mutable results : result_entry list = []
  val mutable hits = 0
  val mutable count_dirs = 0
  val mutable find_all = None
  val mutable current_line_selected = None
  val mutable n_rows = 0

  initializer
    view#append_column vc_file;
    view#append_column vc_hits;
    view#append_column vc_path;
    vc_file#set_sort_column_id 0;
    vc_hits#set_sort_column_id 1;
    vc_path#set_sort_column_id 2;
    preview#set_smart_click false;
    preview#set_highlight_current_line (Some (Color.name_of_gdk (Preferences.tag_color "highlight_current_line")));
    preview#set_show_line_numbers false;
    preview#set_current_line_border_color (`NAME "#707070");
    preview#set_editable false;
    preview#set_cursor_visible false;
    preview#set_pixels_above_lines 3;
    preview#set_pixels_below_lines 3;
    preview#set_border_window_size `LEFT 0;
    preview#buffer#connect#after#mark_set ~callback:begin fun iter mark ->
      match GtkText.Mark.get_name mark with
        | Some "insert" ->
          if preview#buffer#has_selection then begin
            GtkSignal.stop_emit();
            preview#buffer#place_cursor (preview#buffer#get_iter `SEL_BOUND)
          end
        | _ -> ()
    end;
    let bgcolor = preview#misc#style#bg `SELECTED in
    let fgcolor = preview#misc#style#fg `SELECTED in
    let _ = tbuf#create_tag ~name:"find_text_result_hit"
      [`BACKGROUND_GDK bgcolor; `FOREGROUND_GDK fgcolor] in
    let _ = tbuf#create_tag ~name:"find_text_result_linenum"
      [`FOREGROUND "#000000"; `WEIGHT `NORMAL; `BACKGROUND_FULL_HEIGHT_SET true; `SCALE `SMALL] in
    let _ = tbuf#create_tag ~name:"find_text_insensitive" 
      [`FOREGROUND "#b0b0b0"; `STYLE `ITALIC] in
    let _ = Gaux.may (preview#get_window `TEXT) ~f:(fun w -> Gdk.Window.set_cursor w (Gdk.Cursor.create `ARROW)) in
    (*  *)
    ignore (button_remove#connect#clicked ~callback:self#remove_entry);
    ignore (button_stop#connect#clicked ~callback:(fun () -> canceled <- true));
    ignore (button_restart#connect#clicked ~callback:self#restart);
    ignore (button_new_search#connect#clicked ~callback:self#new_search);
    ignore (button_prev_file#connect#clicked ~callback:self#prev_file);
    ignore (button_next_file#connect#clicked ~callback:self#next_file);
    ignore (button_prev_line#connect#clicked ~callback:self#prev_line);
    ignore (button_next_line#connect#clicked ~callback:self#next_line);
    ignore (vbox#connect#destroy ~callback:dialog#destroy);

  method set_options x = options <- Some x
  method private options = match options with Some x -> x | _ -> invalid_arg "Options not specified"
  method text_to_find = self#options.text_find#get

  method set_selected_text_bounds x = selected_text_bounds <- x

  method private canceled = canceled

  method clear () =
    hits <- 0;
    count_dirs <- 0;
    n_rows <- 0;
    results <- [];
    canceled <- false;
    sigids <- [];
    delete_marks <- [];
    GtkThread2.sync model#clear ();
    GtkThread2.sync tbuf#set_text "";
    GtkThread2.sync label_message#set_text "";
    current_line_selected <- None;

  method new_search () = dialog#present();

  method prev_file () =
    let path = match view#selection#get_selected_rows with
      | path :: _ ->
        ignore (GTree.Path.prev path);
        path
      | _ -> GTree.Path.create [List.length results - 1]
    in
    view#selection#select_path path;
    view#scroll_to_cell ~align:(0.6, 0.0) path vc_file;

  method next_file () =
    let path = match view#selection#get_selected_rows with
      | path :: _ ->
        GTree.Path.next path;
        path
      | _ -> GTree.Path.create [0]
    in
    view#selection#select_path path;
    view#scroll_to_cell ~align:(0.4, 0.0) path vc_file;

  method prev_line () = self#move_line `PREV
  method next_line () = self#move_line `NEXT

  method private move_line dir =
    let iter = preview#buffer#get_iter `INSERT in
    let iter =
      if current_line_selected <> None then begin
        if dir = `NEXT then iter#forward_line else iter#backward_line
      end else iter
    in
    self#select_line iter;
    self#activate ~grab_focus:false iter;
    current_line_selected <- Some iter#line;

  method remove_entry () =
    match view#selection#get_selected_rows with
      | path :: _ ->
        let next =
          if GTree.Path.to_string path = GTree.Path.to_string (GTree.Path.create [n_rows - 1])
          then let next = GTree.Path.copy path in ignore ((GTree.Path.prev next)); next
          else path
        in
        ignore (model#remove (model#get_iter path));
        n_rows <- n_rows - 1;
        view#selection#select_path next;
        view#scroll_to_cell ~align:(0.5, 0.0) next vc_file;
      | _ -> ()

  (** restart *)
  method restart () = ignore (Thread.create (fun () -> self#find ?all:find_all ()) ())

  (** find *)
  method find ?all () =
    if String.length self#options.text_find#get > 0 then begin
      self#clear();
      find_all <- all;
      GtkThread2.sync begin fun () ->
        button_stop#misc#set_sensitive true;
        button_restart#misc#set_sensitive false;
        button_prev_file#misc#set_sensitive false;
        button_prev_line#misc#set_sensitive false;
        button_next_line#misc#set_sensitive false;
        button_next_file#misc#set_sensitive false;
        button_new_search#misc#set_sensitive false;
        button_remove#misc#set_sensitive false;
        label_message#set_text "Searching...";
      end ();
      results <- [];
      begin
        try
          if all <> (Some false) then begin
            GtkThread2.sync search_started#call ();
            begin
              match buffer with
                | None ->
                  (* Search  *)
                  self#find_in_path begin
                    match self#options.path with
                      | Project_source -> Project.path_src project
                      | Specified path -> path
                  end
                | Some buffer ->
                  (* Search  *)
                  self#find_in_buffer buffer;
            end;
            GtkThread2.sync begin fun () ->
              button_stop#misc#set_sensitive false;
              label_message#set_text "Please wait...";
            end ();
            if all <> (Some false) then (GtkThread2.sync self#display ());
            GtkThread2.sync search_finished#call ();
          end else begin
            let view = match editor#get_page Editor_types.Current with Some p -> (p#view :> Text.view) | _ -> assert false in
            (* Search  *)
            GtkThread2.sync begin fun () ->
              Find_text_in_buffer.find self#options.direction ~view ~canceled:(fun () -> self#canceled)
            end ();
          end;
        with Canceled -> (GtkThread2.sync self#display ())
      end;
      GtkThread2.sync begin fun () ->
        button_stop#misc#set_sensitive false;
        button_restart#misc#set_sensitive true;
        button_prev_file#misc#set_sensitive (hits > 0 && buffer = None);
        button_prev_line#misc#set_sensitive (hits > 0);
        button_next_line#misc#set_sensitive (hits > 0);
        button_next_file#misc#set_sensitive (hits > 0 && buffer = None);
        button_new_search#misc#set_sensitive true;
        button_remove#misc#set_sensitive (hits > 0 && buffer = None);
        if hits = 0 then label_message#set_text "No matches found"
        else match buffer with
          | None ->
            let n_res = List.length results in
            kprintf label_message#set_text "%d hit%s in %d file%s%s"
              hits (if hits = 1 then "" else "s") n_res (if n_res = 1 then "" else "s")
              (if n_res > 1 then sprintf " (%d %s)" count_dirs
                (if count_dirs = 1 then "directory" else "directories") else "");
          | _ ->
            let bufname = match editor#get_page Editor_types.Current with Some p -> p#get_filename | _ -> assert false in
            kprintf label_message#set_text "%d hits in \xC2\xAB%s\xC2\xBB" hits (Filename.basename bufname)
      end ()
  end

  (** find_in_buffer *)
  method private find_in_buffer buffer =
    let start, stop =
      match selected_text_bounds with
        | None -> None, None
        | Some (start, stop) -> (Some start), (Some stop)
    in
    match Find_text_in_buffer.find_forward ?start ?stop ~all:true ~buffer
        ~regexp:(match self#options.current_regexp with Some x -> x | _ -> assert false)
        ~canceled:(fun () -> self#canceled) () with
      | None -> ()
      | Some lines_involved ->
        let filename = match editor#get_page Editor_types.Current with Some p -> p#get_filename | _ -> assert false in
        results <- {filename = filename; lines = lines_involved} :: results;
        hits <- List.fold_left (fun acc res -> acc + (List.fold_left (fun acc l ->
          acc + (List.length l.offsets)) 0 res.lines)) 0 results

  (** find_in_file *)
  method private find_in_file filename =
    if Sys.file_exists filename then begin
      let ichan = open_in filename in
      let linenum = ref 0 in
      let lines_involved = ref [] in
      let finally () =
        close_in ichan;
        if List.length !lines_involved > 0 then begin
          results <- {filename = filename; lines = (List.rev !lines_involved)} :: results;
        end;
      in
      let l_regexp = match self#options.current_regexp with Some x -> x | _ -> assert false in
      begin
        try
          while true do
            let line = strip_cr (input_line ichan) in
            incr linenum;
            let offsets = ref [] in
            let pos = ref 0 in
            begin
              try
                while true do
                  if canceled then (raise Canceled);
                  if Str.search_forward l_regexp line !pos >= 0 then begin
                    let start, stop = Str.group_beginning 0, Str.group_end 0 in
                    let start_offset = Convert.offset_from_pos line ~pos:start in
                    let stop_offset = Convert.offset_from_pos line ~pos:stop in
                    offsets := (start_offset, stop_offset) :: !offsets;
                    pos := stop;
                    hits <- hits + 1;
                  end
                done
              with Not_found -> ()
            end;
            if List.length !offsets > 0 then begin
              lines_involved := {line = line; linenum = !linenum; offsets = (List.rev !offsets); marks = []} ::
                !lines_involved;
            end
          done
        with
          | End_of_file -> ()
          | Canceled as ex -> (finally (); raise ex)
      end;
      finally()
    end

  (** find_in_path *)
  method private find_in_path path =
    let files = File.Util.ls ~dir:path ~pattern:(match self#options.pattern with None -> "*" | Some x -> x) in
    let files = List.map (fun x -> path // x) files in
    let _, files = List.partition (fun x -> if Sys.file_exists x then (Sys.is_directory x) else false) files in
    let old_hits = hits in
    List.iter self#find_in_file files;
    if hits > old_hits then (count_dirs <- count_dirs + 1);
    if self#options.recursive then
      begin
        let directories = File.Util.lsd ~dir:path ~pattern:"*" in
        let directories = List.map (fun x -> path // x) directories in
        List.iter self#find_in_path directories;
      end

  (** replace *)
  method replace () = 
    let dialog_confirm_replace = GWindow.dialog ~show:false ~title:"Confirm Replace" ~width:500
      ~type_hint:`DIALOG ~urgency_hint:true ~border_width:8
      ~position:`CENTER ?parent:(GWindow.toplevel self) () in
    dialog_confirm_replace#vbox#set_border_width 8;
    dialog_confirm_replace#vbox#set_spacing 8;
    let table = GPack.table ~col_spacings:8 ~row_spacings:5 ~packing:dialog_confirm_replace#vbox#pack () in
    let _ = GMisc.label ~text:"File:" ~xalign:0.0 ~packing:(table#attach ~top:0 ~left:0) () in
    let _ = GMisc.label ~text:"Text found:" ~xalign:0.0 ~packing:(table#attach ~top:1 ~left:0) () in
    let _ = GMisc.label ~text:"Replace with:" ~xalign:0.0 ~packing:(table#attach ~top:2 ~left:0) () in
    let entry_filename = GEdit.entry ~editable:false ~packing:(table#attach ~top:0 ~left:1 ~expand:`X) () in
    let entry_find = GEdit.entry ~editable:false ~packing:(table#attach ~top:1 ~left:1 ~expand:`X) () in
    let entry_repl = GEdit.combo_box_entry
      ~model:self#options.h_repl.model ~text_column:self#options.h_repl.column
      ~packing:(table#attach ~top:2 ~left:1 ~expand:`X) () in
    entry_filename#misc#set_can_focus false;
    entry_find#misc#set_can_focus false;
    entry_repl#entry#misc#grab_focus();
    dialog_confirm_replace#add_button "Skip" `SKIP;
    dialog_confirm_replace#add_button "Skip File" `SKIP_FILE;
    dialog_confirm_replace#add_button "Replace" `REPLACE;
    dialog_confirm_replace#add_button "Replace All" `REPLACE_ALL;
    dialog_confirm_replace#add_button "Done" `DONE;
    let replace_all = ref false in
    view#selection#unselect_all();
    let buffers = ref [] in
(*    let old_autocomp_enabled = project.Project.autocomp_enabled in
    project.Project.autocomp_enabled <- false;*)
    try
      List.iter begin function {filename = filename; lines = lines} as res ->
        let pagefile = Editor_types.File (File.create filename ()) in
        let page = match editor#get_page pagefile with
          | None ->
            editor#open_file ~active:false ~offset:0 filename;
            begin
              match editor#get_page pagefile with
                | None -> assert false
                | Some page -> page
            end
          | Some page ->
            (*if not page#load_complete then (ignore (page#load()));*)
            if not page#load_complete then (ignore (editor#load_page ~scroll:false page));
            page
        in
        let old_error_indication_enabled = page#error_indication#enabled in
        page#error_indication#set_enabled false;
        page#buffer#undo#begin_block ~name:"replace";
        buffers := page#buffer :: !buffers; 
        self#place_marks res;
        let path =
          try
            let path = List.hd view#selection#get_selected_rows in
            GTree.Path.next path;
            path
          with Failure "hd" -> (GTree.Path.create [0])
        in
        if not !replace_all then begin
          view#selection#select_path path;
          view#scroll_to_cell path vc_file;
        end;
        let i = ref 0 in
        let l_regexp = match self#options.current_regexp with Some x -> x | _ -> assert false in
        let replacement_text m1 m2 =
          let start = page#buffer#get_iter_at_mark (`NAME m1) in
          let stop = page#buffer#get_iter_at_mark (`NAME m2) in
          let text = page#buffer#get_text ~start ~stop () in
          let templ =
            try
              if self#options.use_regexp then Str.replace_first l_regexp self#options.text_repl text else self#options.text_repl
            with Failure _ -> self#options.text_repl
          in
          start, stop, templ
        in
        let replace m1 m2 =
          let start, stop, _ = replacement_text m1 m2 in
          let templ = entry_repl#entry#text in
          page#buffer#delete ~start ~stop;
          page#buffer#insert templ;
          if page#buffer#lexical_enabled then begin
            let iter = page#buffer#get_iter `INSERT in
            Lexical.tag page#view#buffer  
              ~start:((iter#backward_chars (Glib.Utf8.length templ))#set_line_index 0)
              ~stop:iter#forward_line;
          end;
          page#buffer#move_mark (`NAME m2) ~where:(page#buffer#get_iter `INSERT);
        in
        try
          List.iter begin fun {line=line; linenum=linenum; offsets=offsets; marks=marks} ->
            begin
              match marks with [] -> () | marks ->
                List.iter begin fun (m1, m2) ->
                  editor#goto_view page#view;
                  if not !replace_all then (self#select_line (preview#buffer#get_iter (`LINE !i)));
                  page#view#tbuffer#select_marks ~start:(`NAME m1) ~stop:(`NAME m2);
                  let text = page#view#tbuffer#selection_text () in
                  let _, _, templ = replacement_text m1 m2 in
                  entry_filename#set_text filename;
                  entry_find#set_text text;
                  entry_repl#entry#set_text templ;
                  if not !replace_all then begin
                    page#view#scroll_lazy (page#view#buffer#get_iter_at_mark (`NAME m1));
                    match dialog_confirm_replace#run () with
                      | `SKIP -> ();
                      | `SKIP_FILE -> raise Skip_file;
                      | `REPLACE -> replace m1 m2;
                      | `REPLACE_ALL -> replace_all := true;
                      | _ -> raise Exit;
                  end;
                  if !replace_all then (replace m1 m2);
                end marks
            end;
            incr i;
          end res.lines;
          page#error_indication#set_enabled old_error_indication_enabled;
        with Skip_file -> ()
      end results;
      List.iter (fun b -> b#undo#end_block()) !buffers;
      (*project.Project.autocomp_enabled <- old_autocomp_enabled;*)
      raise Exit
    with Exit ->
      dialog_confirm_replace#destroy()
      

  (** place_marks *)
  method private place_marks res =
    try
      let page =
        match editor#get_page (Editor_types.File (File.create res.filename ())) with
          | None -> raise Not_found
          | Some page ->
            (*if not page#load_complete then (ignore (page#load()));*)
            if not page#load_complete then (ignore (editor#load_page ~scroll:false page));
            page
      in
      (*let max_ln = List.fold_left (fun acc {linenum=x} -> max x acc) 0 res.lines in
      if page#buffer#line_count < max_ln then (raise (Buffer_changed (page#buffer#line_count - max_ln, "", "")));*)
      List.iter begin function
        | ({line=line; linenum=ln; offsets=offsets; marks=marks} as result_line) when marks = [] ->
          begin
            let ln = ln - 1 in
            List.iter begin fun (start, stop) ->
              let iter = page#buffer#get_iter (`LINECHAR (ln, 0)) in
              let bline = page#buffer#get_text ~start:iter ~stop:iter#forward_to_line_end () in
              if (Project.convert_to_utf8 project (strip_cr line)) = (strip_cr bline) then begin
                let name_start = new_mark_name() in
                let _ = page#buffer#create_mark ~name:name_start (iter#forward_chars start) in
                delete_marks <- (fun () -> page#buffer#delete_mark (`NAME name_start)) :: delete_marks;
                let name_stop = new_mark_name() in
                let _ = page#buffer#create_mark ~name:name_stop (iter#forward_chars stop) in
                delete_marks <- (fun () -> page#buffer#delete_mark (`NAME name_stop)) :: delete_marks;
                result_line.marks <- result_line.marks @ [(name_start, name_stop)];
              end else (raise (Buffer_changed ((ln + 1), bline, line)))
            end offsets;
          end
        | _ -> ()
      end res.lines
    with
      | Not_found -> begin
          let sigid = editor#connect#add_page ~callback:begin fun page ->
            if page#get_filename = res.filename then (self#place_marks res)
          end in
          sigids <- sigid :: sigids
        end
      | Buffer_changed (n, bline, line) (*as ex*) -> begin
        if selected_text_bounds = None then begin
          fprintf stderr "Find_text_output: exception Buffer_changed\nFile %s: at line %d found %S, expected %S\n%!"
            res.filename n bline line;
        end;
        self#set_insensitive()
      end

  (** select_line *)
  method private select_line iter =
    let where = iter#set_line_offset 0 in
    preview#buffer#place_cursor ~where;
    preview#buffer#remove_tag_by_name "find_text_result_line"
      ~start:preview#buffer#start_iter ~stop:preview#buffer#end_iter;
    let _ = self#get_selected_result () in
    preview#buffer#apply_tag_by_name "find_text_result_line"
      ~start:(iter#set_line_offset 0)
      ~stop:((iter#set_line_offset 0)#forward_to_line_end);
    preview#scroll_lazy (preview#buffer#get_iter_at_mark `INSERT);

  (** get_selected_result *)
  method private get_selected_result () =
    let path =
      try List.hd view#selection#get_selected_rows
      with Failure "hd" -> begin
        let first = GTree.Path.create [0] in
        view#selection#select_path first;
        first
      end
    in
    let row = model#get_iter path in
    let file = model#get ~row ~column:col_file in
    let path = model#get ~row ~column:col_path in
    let filename = path // file in
    List.find (fun {filename=fn} -> fn = filename) results

  (** set_insensitive *)
  method private set_insensitive () = 
    preview#buffer#remove_tag_by_name "find_text_result_line"
      ~start:preview#buffer#start_iter ~stop:preview#buffer#end_iter;
    preview#buffer#apply_tag_by_name "find_text_insensitive"
      ~start:preview#buffer#start_iter ~stop:preview#buffer#end_iter;

  (** activate *)
  method private activate ?(grab_focus=false) iter = 
    let res = self#get_selected_result () in
    try
      let lines_involved = res.lines in
      let filename = res.filename in
      editor#open_file ~active:true ~offset:0 filename;
      let page =
        match editor#get_page (Editor_types.File (File.create filename ()))
        with None -> raise Not_found | Some page -> page
      in
      self#place_marks res;
      begin
        match List.nth lines_involved iter#line with
          | {marks = ((mark_start, mark_stop) :: _) } ->
            let where = page#buffer#get_iter_at_mark (`NAME mark_start) in
            page#buffer#select_range where (page#buffer#get_iter_at_mark (`NAME mark_stop));
            page#view#scroll_lazy where;
            if grab_focus then (page#view#misc#grab_focus()) else (preview#misc#grab_focus())
          | _ -> ()
      end
    with
      | Not_found -> (if Oe_config.ocamleditor_debug then assert false)
      | GText.No_such_mark _ -> begin
          List.iter (fun x -> x.marks <- []) res.lines;
          self#activate ~grab_focus iter;
        end

  (** display *)
  method private display () = 
    (* Sort *)
    List.iter begin fun result ->
      result.lines <- List.sort (fun {linenum = l1} {linenum = l2} -> compare l1 l2) result.lines
    end results;
    results <- List.sort (fun {filename=f1} {filename=f2} -> compare f1 f2) results;
    (*  *)
    Gaux.may (preview#get_window `TEXT) ~f:(fun w -> Gdk.Window.set_cursor w (Gdk.Cursor.create `ARROW));
(*    (* Line result at iter *)
    let result_line iter =
      let res = self#get_selected_result () in
      let lines_involved = res.lines in
      List.nth lines_involved iter#line
    in*)
    (* We track marks for future removal. *)
    List.iter begin function {filename=filename; lines=lines_involved} as res->
      let row = model#append () in
      model#set ~row ~column:col_file (Filename.basename filename);
      model#set ~row ~column:col_hits (List.fold_left (fun acc {offsets=x} -> acc + (List.length x)) 0 lines_involved);
      model#set ~row ~column:col_path (Filename.dirname filename);
      n_rows <- n_rows + 1;
      self#place_marks res;
    end results;
    ignore (view#selection#connect#after#changed ~callback:begin fun () ->
      try
        let path = List.hd view#selection#get_selected_rows in
        let row = model#get_iter path in
        let file = model#get ~row ~column:col_file in
        let path = model#get ~row ~column:col_path in
        let filename = path // file in
        tbuf#set_lexical_enabled (filename ^^ ".ml" || filename ^^ ".mli" || filename ^^ ".mll" || filename ^^ ".mly");
        let res = List.find (fun {filename=fn} -> fn = filename) results in
        let lines_involved = res.lines in
        tbuf#delete ~start:tbuf#start_iter ~stop:tbuf#end_iter;
        let i = ref 0 in
        let maxlinenum = List.fold_left (fun acc {linenum=x} -> max acc x) 0 lines_involved in
        let maxlinenum_length = String.length (string_of_int maxlinenum) in
        List.iter begin fun {line=line; linenum=linenum; offsets=hits} ->
          begin
            try
              let line = Project.convert_to_utf8 project line in
              let scarto, line = 0, (*ltrim*) line in
              let line = sprintf "%s: %s"
                (Miscellanea.lpad (string_of_int linenum) ' ' maxlinenum_length) line in
              tbuf#insert (line ^ (if !i = List.length lines_involved - 1 then "" else "\n"));
              let iter = tbuf#get_iter `INSERT in
              if tbuf#lexical_enabled then begin
                Lexical.tag (tbuf :> GText.buffer)
                  ~start:((iter#backward_chars (Glib.Utf8.length line))#set_line_index 0)
                  ~stop:iter#forward_line;
              end;
              tbuf#apply_tag_by_name "find_text_result_linenum" 
                ~start:(tbuf#get_iter (`LINECHAR (!i, 0)))
                ~stop:(tbuf#get_iter (`LINECHAR (!i, maxlinenum_length + 2)));
              List.iter begin fun (start, stop) ->
                let start = start + maxlinenum_length + 2 - scarto in
                let stop = stop + maxlinenum_length + 2 - scarto in
                tbuf#apply_tag_by_name "find_text_result_hit"
                  ~start:(tbuf#get_iter (`LINECHAR (!i, start)))
                  ~stop:(tbuf#get_iter (`LINECHAR (!i, stop)));
              end hits;
            with Glib.Convert.Error (Glib.Convert.ILLEGAL_SEQUENCE, _) -> ()
          end;
          incr i
        end lines_involved;
        tbuf#place_cursor ~where:tbuf#start_iter;
        current_line_selected <- None;
      with Failure "hd" -> ()
    end);
    view#connect#after#row_activated ~callback:begin fun path iter ->
      ignore (self#select_line (tbuf#get_iter `SEL_BOUND));
      preview#misc#grab_focus();
    end;
    (* lines preview focus_in  *)
    preview#event#connect#focus_in ~callback:begin fun ev ->
      if tbuf#char_count > 0 then begin
        let bgcolor = Color.name_of_gdk (Preferences.tag_color "highlight_current_line") in
        Gtk_util.set_tag_paragraph_background preview#highlight_current_line_tag bgcolor;
        let iter = tbuf#get_iter `INSERT in
        self#select_line iter;
        self#activate ~grab_focus:false iter;
        current_line_selected <- (Some iter#line);
      end;
      false
    end;
    (* lines preview focus_out  *)
    preview#event#connect#focus_out ~callback:begin fun ev ->
      false
    end;
    (* double-click event on the preview activates the line. *)
    preview#event#connect#button_press ~callback:begin fun ev ->
      let x = int_of_float (GdkEvent.Button.x ev) in
      let y = int_of_float (GdkEvent.Button.y ev) in
      let x, y = preview#window_to_buffer_coords ~tag:`TEXT ~x ~y in
      let iter = preview#get_iter_at_location ~x ~y in
      match GdkEvent.get_type ev with
        | `TWO_BUTTON_PRESS ->
          self#select_line iter;
          self#activate ~grab_focus:true iter;
          preview#buffer#place_cursor (iter#set_line_index 0);
          true
        | `BUTTON_PRESS ->
          self#select_line iter;
          self#activate ~grab_focus:false iter;
          false
        | _ -> false
    end;
    (* Lines preview: key_press event moves across the lines and activates them. *)
    preview#event#connect#key_press ~callback:begin fun ev ->
      let key = GdkEvent.Key.keyval ev in
      let iter = preview#buffer#get_iter `INSERT in
      if key = _Up then self#prev_line ()
      else if key = _Down then self#next_line ()
      else if List.mem key [_Right; _Left; _Return] then begin
        self#activate ~grab_focus:true iter;
      end;
      true
    end;
    (*  *)
    preview#event#connect#key_release ~callback:begin fun ev ->
      let key = GdkEvent.Key.keyval ev in
      if key = GdkKeysyms._Tab then ()
      else if key = GdkKeysyms._ISO_Left_Tab then (view#misc#grab_focus());
      true;
    end;
    (*  *)
    ignore (preview#connect#destroy ~callback:begin fun () ->
      List.iter (fun f -> try f () with GText.No_such_mark _ -> ()) delete_marks;
      List.iter editor#connect#disconnect sigids
    end);
    view#selection#select_path (GTree.Path.create [0]);
    if editor_buffer <> None then (lsw#misc#hide ())

  method connect = new signals ~search_started ~search_finished
end

and search_started () = object (self) inherit [unit] signal () as super end
and search_finished () = object (self) inherit [unit] signal () as super end
and signals ~search_started ~search_finished =
object (self)
  inherit ml_signals [search_started#disconnect; search_finished#disconnect]
  method search_started = search_started#connect ~after
  method search_finished = search_finished#connect ~after
end