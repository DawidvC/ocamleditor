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
open GUtil
open Miscellanea

class ['a] toolbar ~(messages : Messages.messages) ~(editor : Editor.editor) () =
  let tool_messages_clicked    = new tool_messages_clicked () in
  let toolbar                  = GButton.toolbar ~style:`ICONS () in
  let _                        = toolbar#set_icon_size `MENU in
  let tool_new_file            = GButton.tool_button ~stock:`NEW ~label:"New" () in
  let tool_open_file           = GButton.tool_button ~stock:`OPEN ~label:"Open" () in
  let tool_save                = GButton.tool_button ~stock:`SAVE ~homogeneous:false ~label:"Save" () in
  let tool_save_all            = Menu_tool_button.create ~homogeneous:false ~toolbar ~label:"Save All" () in
  let tool_close_file          = GButton.tool_button ~stock:`CLOSE ~label:"Close" () in
  let tool_undo                = GButton.tool_button ~stock:`UNDO ~label:"Undo" () in
  let tool_redo                = GButton.tool_button ~stock:`REDO ~label:"Redo" () in
  let tool_find_repl           = GButton.tool_button ~stock:`FIND_AND_REPLACE ~label:"Find and Replace" () in
  let tool_item_find_entry     = GButton.tool_item ~homogeneous:false () in
  let tool_find                = GButton.tool_button ~label:"Find" () in
  let tool_messages            = GButton.toggle_tool_button ~active:messages#visible ~label:"Messages" ~homogeneous:false () in
  let tool_messages_sign       = tool_messages#connect#clicked ~callback:(fun () -> tool_messages_clicked#call (not messages#visible)) in
  let tool_eval                = GButton.tool_button ~stock:`EXECUTE ~label:"Toplevel" () in
  let tool_clean               = Menu_tool_button.create ~toolbar ~homogeneous:false () in
  let tool_compile_file        = GButton.tool_button ~label:"Compile File" () in
  let tool_build               = Menu_tool_button.create ~toolbar ~homogeneous:false () in
  let tool_link                = Menu_tool_button.create ~toolbar ~homogeneous:false () in
  let tool_run                 = Menu_tool_button.create ~toolbar ~homogeneous:false () in
  let tool_back                = Menu_tool_button.create ~toolbar ~stock:`GO_BACK ~label:"Previous Location" ~homogeneous:false () in
  let tool_forward             = Menu_tool_button.create ~toolbar ~stock:`GO_FORWARD ~label:"Next Location" ~homogeneous:false () in
  let tool_last_edit_loc       = GButton.tool_button ~stock:`GOTO_LAST ~label:"Last Edit Location" () in
  let tool_entry_find          = GEdit.combo_box_entry
    ~focus_on_click:false
    ~model:Find_text.status.Find_text.h_find.Find_text.model
    ~text_column:Find_text.status.Find_text.h_find.Find_text.column
    ~packing:tool_item_find_entry#add ()
  in
  let _ = tool_entry_find#entry#set_text begin
    match Find_text.status.Find_text.h_find.Find_text.model#get_iter_first with
      | None -> ""
      | Some row -> Find_text.status.Find_text.h_find.Find_text.model#get ~row
        ~column:Find_text.status.Find_text.h_find.Find_text.column
  end in
  let _ = Find_text.status.Find_text.text_find#connect#changed ~callback:tool_entry_find#entry#set_text in
object (self)
  inherit GObj.widget toolbar#as_widget
  method children = toolbar#children
  method tool_new_file = tool_new_file
  method tool_open_file = tool_open_file
  method tool_save = tool_save
  method tool_save_all = tool_save_all
  method tool_close_file = tool_close_file
  method tool_undo = tool_undo
  method tool_redo = tool_redo
  method tool_find_repl = tool_find_repl
  method tool_entry_find = tool_entry_find
  method tool_find = tool_find
  method tool_eval = tool_eval
  method tool_compile_file = tool_compile_file
  method tool_back = tool_back
  method tool_forward = tool_forward
  method tool_last_edit_loc = tool_last_edit_loc
  method tool_messages_handler_block () = tool_messages#misc#handler_block tool_messages_sign
  method tool_messages_handler_unblock () = tool_messages#misc#handler_unblock tool_messages_sign
  method tool_messages_set_active = tool_messages#set_active

  initializer
    (** File *)
    toolbar#insert tool_new_file;
    toolbar#insert tool_open_file;
    toolbar#insert tool_save;
    tool_save#set_icon_widget (GMisc.image ~pixbuf:Icons.save_16 ())#coerce;
    toolbar#insert tool_save_all#as_tool_item;
    tool_save_all#set_icon_widget (GMisc.image ~pixbuf:Icons.save_all_16 ())#coerce;
    (*tool_save_all#connect#popup ~callback:save_all_popup#call;*)
    toolbar#insert tool_close_file;
    (** Undo/Redo *)
    let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
    toolbar#insert tool_undo;
    toolbar#insert tool_redo;
    (** Find/replace *)
    let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
    toolbar#insert tool_find_repl;
    toolbar#insert tool_item_find_entry;
    toolbar#insert tool_find;
    tool_find#set_icon_widget (GMisc.image ~pixbuf:Icons.search_again_16 ())#coerce;
    (** Messages, eval, compile file *)
    let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
    toolbar#insert tool_messages;
    toolbar#insert tool_eval;
    tool_eval#misc#set_tooltip_text "Eval in Toplevel";
    toolbar#insert tool_compile_file;
    tool_compile_file#set_icon_widget (Icons.create Icons.compile_file_16)#coerce;
    (** Clean, Build, Run *)
    let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
    toolbar#insert tool_clean#as_tool_item;
    tool_clean#set_icon_widget (GMisc.image ~pixbuf:Icons.clear_build_16 ())#coerce;
    toolbar#insert tool_build#as_tool_item;
    tool_build#set_icon_widget (GMisc.image ~pixbuf:Icons.compile_all_16 ())#coerce;
    tool_build#misc#set_tooltip_text "Compile only";
    toolbar#insert tool_link#as_tool_item;
    tool_link#set_icon_widget (GMisc.image ~pixbuf:Icons.build_16 ())#coerce;
    tool_link#misc#set_tooltip_text "Build";
    toolbar#insert tool_run#as_tool_item;
    tool_run#set_icon_widget (GMisc.image ~pixbuf:Icons.start_16 ())#coerce;
    (** Location History *)
    let _ = GButton.separator_tool_item ~packing:toolbar#insert () in
    toolbar#insert tool_back#as_tool_item;
    toolbar#insert tool_forward#as_tool_item;
    toolbar#insert tool_last_edit_loc;
    ()

  method bind_signals : 'a -> unit = fun browser ->
    (** file *)
    ignore (tool_new_file#connect#clicked ~callback:browser#dialog_file_new);
    ignore (tool_open_file#connect#clicked ~callback:editor#dialog_file_open);
    ignore (tool_save#connect#clicked ~callback:begin fun () ->
      Gaux.may ~f:editor#save (editor#get_page Editor_types.Current)
    end);
    ignore (tool_save_all#connect#clicked ~callback:browser#save_all);
    ignore (tool_save_all#connect#popup ~callback:begin fun (label, menu) ->
      List.iter begin fun p ->
        if p#view#buffer#modified then begin
          let item = GMenu.menu_item ~label:(Filename.basename p#get_filename) ~packing:menu#append () in
          ignore (item#connect#activate ~callback:p#save);
        end
      end editor#pages;
    end);
    ignore (tool_close_file#connect#clicked ~callback:(fun () -> editor#with_current_page editor#dialog_confirm_close));
    (** undo/redo *)
    ignore (tool_undo#connect#clicked ~callback:(fun () -> editor#with_current_page (fun p -> p#undo())));
    ignore (tool_redo#connect#clicked ~callback:(fun () -> editor#with_current_page (fun p -> p#redo())));
    (** find/replace *)
    let search_again () =
      Find_text.update_status
        ~project:browser#current_project
        ~text_find:tool_entry_find#entry#text ();
      browser#search_again ();
    in
    ignore (tool_find_repl#connect#clicked ~callback:(fun () ->
      browser#find_and_replace ?find_all:None ?search_word_at_cursor:None ()));
    ignore (tool_entry_find#entry#event#connect#key_press ~callback:begin fun ev ->
      if GdkEvent.Key.keyval ev = GdkKeysyms._Return then begin
        search_again ();
        true
      end else false
    end);
    ignore (tool_find#connect#clicked ~callback:search_again);
    (** Messages, eval, compile file *)
    ignore (self#connect#tool_messages_clicked ~callback:(fun _ -> ((browser#set_messages_visible (not messages#visible)) : unit)));
    ignore (tool_eval#connect#clicked ~callback:begin fun () ->
      Gaux.may ~f:(fun p -> p#ocaml_view#obuffer#send_to_shell ()) (editor#get_page Editor_types.Current)
    end);
    ignore (tool_compile_file#connect#clicked ~callback:begin fun () ->
      editor#with_current_page (fun p -> p#compile_buffer ~commit:false ())
    end);
    (** Build configurations *)
    (* clean *)
    ignore (tool_clean#connect#clicked ~callback:begin fun () ->
      Gaux.may (browser#get_default_build_config ()) ~f:begin fun default_bconf ->
        ignore (Bconf_console.exec ~project:browser#current_project ~editor `CLEAN default_bconf)
      end
    end);
    ignore (tool_clean#connect#popup ~callback:begin fun (label, menu) ->
      Gaux.may (browser#get_default_build_config ()) ~f:begin fun default_bconf ->
        label := sprintf "Clean \xC2\xAB%s\xC2\xBB" default_bconf.Bconf.name;
        let bconfigs = browser#current_project.Project.build in
        List.iter begin fun tg ->
          let item = GMenu.menu_item ~label:tg.Bconf.name ~packing:menu#add () in
          ignore (item#connect#activate ~callback:begin fun () ->
            ignore (Bconf_console.exec ~project:browser#current_project ~editor `CLEAN tg)
          end);
        end bconfigs;
      end
    end);
    (* build *)
    ignore (tool_build#connect#clicked ~callback:begin fun () ->
      Gaux.may (browser#get_default_build_config ()) ~f:begin fun default_bconf ->
        ignore (Bconf_console.exec ~project:browser#current_project ~editor `COMPILE_ONLY default_bconf)
      end
    end);
    ignore (tool_build#connect#popup ~callback:begin fun (label, menu) ->
      Gaux.may (browser#get_default_build_config ()) ~f:begin fun default_bconf ->
        label := sprintf "Compile \xC2\xAB%s\xC2\xBB" default_bconf.Bconf.name;
        let bconfigs = browser#current_project.Project.build in
        List.iter begin fun tg ->
          let item = GMenu.menu_item ~label:tg.Bconf.name ~packing:menu#add () in
          ignore (item#connect#activate ~callback:begin fun () ->
            ignore (Bconf_console.exec ~project:browser#current_project ~editor `COMPILE_ONLY tg)
          end);
        end bconfigs;
      end
    end);
    (* link *)
    ignore (tool_link#connect#clicked ~callback:begin fun () ->
      Gaux.may (browser#get_default_build_config ()) ~f:begin fun default_bconf ->
        ignore (Bconf_console.exec ~project:browser#current_project ~editor `COMPILE default_bconf)
      end
    end);
    ignore (tool_link#connect#popup ~callback:begin fun (label, menu) ->
      Gaux.may (browser#get_default_build_config ()) ~f:begin fun default_bconf ->
        label := sprintf "Build \xC2\xAB%s\xC2\xBB" default_bconf.Bconf.name;
        let bconfigs = browser#current_project.Project.build in
        List.iter begin fun tg ->
          let item = GMenu.menu_item ~label:tg.Bconf.name ~packing:menu#add () in
          ignore (item#connect#activate ~callback:begin fun () ->
            ignore (Bconf_console.exec ~project:browser#current_project ~editor `COMPILE tg)
          end); ()
        end bconfigs;
      end
    end);
    (* run *)
    ignore (tool_run#connect#clicked ~callback:begin fun () ->
      Gaux.may (browser#get_default_runtime_config ()) ~f:begin fun rc ->
        let bc = List.find (fun b -> b.Bconf.id = rc.Rconf.id_build) browser#current_project.Project.build in
        ignore (Bconf_console.exec ~project:browser#current_project ~editor (`RCONF rc) bc)
      end
    end);
    ignore (tool_run#connect#popup ~callback:begin fun (label, menu) ->
      Gaux.may (browser#get_default_runtime_config ()) ~f:begin fun default_rc ->
        Gaux.may (browser#get_default_build_config ()) ~f:begin fun default_bconf ->
          label := sprintf "Run \xC2\xAB%s\xC2\xBB" default_rc.Rconf.name;
          let bconfigs = browser#current_project.Project.build in
          List.iter begin fun rc ->
            let item = GMenu.menu_item ~label:rc.Rconf.name ~packing:menu#add () in
            ignore (item#connect#activate ~callback:begin fun () ->
              try
                let bc = List.find (fun b -> b.Bconf.id = rc.Rconf.id_build) bconfigs in
                ignore (Bconf_console.exec ~project:browser#current_project ~editor (`RCONF rc) bc)
              with Not_found -> ()
            end);
          end browser#current_project.Project.runtime;
        end
      end
    end);
    (** Location History *)
    tool_back#connect#clicked ~callback:(fun () -> browser#goto_location `PREV);
    tool_forward#connect#clicked ~callback:(fun () -> browser#goto_location `NEXT);
    tool_last_edit_loc#connect#clicked ~callback:(fun () -> browser#goto_location `LAST);
    tool_back#connect#popup ~callback:(fun (dir, menu) -> browser#create_menu_history `BACK ~menu);
    tool_forward#connect#popup ~callback:(fun (dir, menu) -> browser#create_menu_history `FORWARD ~menu);
    ()

  method update current_project =
    let dbf = match current_project with None -> None | Some x -> Project.default_build_config x in
    let editor_empty = List.length editor#pages = 0 in
    let current_modified = match editor#get_page Editor_types.Current
      with Some p when p#buffer#modified -> true | _ -> false in
    tool_messages#misc#set_sensitive true;
    tool_new_file#misc#set_sensitive (current_project <> None);
    tool_open_file#misc#set_sensitive (current_project <> None);
    tool_save#misc#set_sensitive (current_project <> None && current_modified);
    tool_close_file#misc#set_sensitive (not editor_empty);
    (*  *)
    tool_find_repl#misc#set_sensitive (current_project <> None && not editor_empty);
    tool_find#misc#set_sensitive (current_project <> None && not editor_empty);
    tool_item_find_entry#misc#set_sensitive (current_project <> None && not editor_empty);
    (*  *)
    tool_clean#misc#set_sensitive (current_project <> None && dbf <> None);
    tool_build#misc#set_sensitive (current_project <> None && dbf <> None);
    tool_run#misc#set_sensitive (current_project <> None && dbf <> None);
    editor#with_current_page begin fun p ->
      let name = Filename.basename p#get_filename in
      if name ^^ ".ml" || name ^^ ".mli" then begin
        kprintf tool_compile_file#misc#set_tooltip_text "Compile \xC2\xAB%s\xC2\xBB" name;
        tool_compile_file#misc#set_sensitive true
      end else begin
        tool_compile_file#misc#set_tooltip_text "";
        tool_compile_file#misc#set_sensitive false
      end
    end;
    begin
      let back, forward, last = editor#location_history_is_empty () in
      try
        tool_back#misc#set_sensitive (not back);
        tool_forward#misc#set_sensitive (not forward);
        tool_last_edit_loc#misc#set_sensitive (not last);
      with _ -> ()
    end

  method connect = new signals ~tool_messages_clicked
end  

(** Signals *)
and tool_messages_clicked () = object inherit [bool] signal () as super end

and signals ~tool_messages_clicked =
object 
  inherit ml_signals [tool_messages_clicked#disconnect]
  method tool_messages_clicked = tool_messages_clicked#connect ~after
end



(*let signals = [];;
let signals = List.map (fun x -> x ^ "_clicked") signals;;

List.iter begin fun name -> Printf.printf "let %s = new %s () in\n"  name name end signals;;
List.iter begin fun name -> Printf.printf "and %s () = object (self) inherit [unit] signal () as super end\n" name end signals;;
List.iter begin fun name -> Printf.printf "%s#disconnect; " name end signals;;
List.iter begin fun name -> Printf.printf "~%s " name end signals;;
List.iter begin fun name -> Printf.printf "method %s = %s#connect ~after\n" name name end signals;;*)







