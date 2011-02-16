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


open GUtil
open Task

class view ?packing () =
  let changed = new changed () in
  let xalign = 0.0 in
  let vbox = GPack.vbox ~spacing:8 ?packing () in
  let entry_name = GEdit.entry ~packing:vbox#pack () in
  let entry_always = GButton.check_button ~label:"Always run when building project"
    ~active:true ~packing:vbox#add () in
  (* Phase *)
  let box = GPack.vbox ~packing:vbox#pack () in
  let _ = GMisc.label ~text:"Phase" ~xalign ~packing:box#add () in
  let phases = [Before_clean; Clean; After_clean; Before_compile; Compile; After_compile] in
  let strings = List.map Task.descr_of_phase phases in
  let combo_phase, _ = GEdit.combo_box_text ~strings ~active:0 ~packing:box#add () in
  let _ = entry_always#connect#toggled ~callback:begin fun () ->
    combo_phase#misc#set_sensitive entry_always#active;
  end in
  (* Working dir *)
  let box = GPack.vbox ~packing:vbox#pack ~show:true () in
  let _ = GMisc.label ~markup:"Working directory <small>(relative to the project source path)</small>" ~xalign ~packing:box#add () in
  let box = GPack.hbox ~spacing:5 ~packing:box#pack () in
  let button_dir = GEdit.entry ~packing:box#add () in
  (* Program *)
  let box = GPack.vbox ~packing:vbox#pack () in
  let _ = GMisc.label ~text:"Command" ~xalign ~packing:box#add () in
  let hbox = GPack.hbox ~spacing:5 ~packing:box#pack () in
  let entry_cmd = GEdit.entry ~packing:hbox#add () in
  let button_cmd = GButton.button ~label:"  ...  " ~packing:hbox#pack () in
  let _ = button_cmd#connect#clicked ~callback:begin fun () ->
    let dialog = GWindow.file_chooser_dialog ~action:`OPEN ~position:`CENTER
      ~title:"Choose program..." ~icon:Icons.oe
      ~modal:true ~show:false () in
    dialog#add_select_button_stock `OK `OK;
    dialog#add_button_stock `CANCEL `CANCEL;
    dialog#add_filter (GFile.filter ~name:"All Files" ~patterns:["*"] ());
    dialog#add_filter (GFile.filter ~name:"OCaml Scripts" ~patterns:["*.ml"] ());
    dialog#add_filter (GFile.filter ~name:"Shell Scripts" ~patterns:["*.sh"; "*.cmd"; "*.bat"] ());
    dialog#add_filter (GFile.filter ~name:"Executables" ~patterns:["*.exe"] ());
    match dialog#run () with
      | `OK ->
        Gaux.may dialog#filename ~f:entry_cmd#set_text;
        dialog#destroy()
      | _ -> dialog#destroy()
  end in
  (* Command line arguments *)
  let box = GPack.vbox ~packing:vbox#pack () in
  let _ = GMisc.label
    ~markup:"Command line arguments <small>(separated by spaces, use \" to quote and \\\" inside quoted arguments)</small>"
    ~xalign ~packing:box#add () in
  let entry_args = GEdit.entry ~packing:box#add () in
  (* Environment *)
  let box = GPack.vbox ~packing:vbox#pack () in
  let _ = GMisc.label ~markup:"Environment (<small><tt>NAME=VALUE</tt></small>)" ~xalign ~packing:box#add () in
  let entry_env = Entry_env.create ~packing:box#add () in
object (self)
  inherit GObj.widget vbox#as_widget
  val mutable etask = None

  initializer
    ignore (entry_name#connect#changed
      ~callback:(self#update (fun etask -> etask.Task.name <- entry_name#text)));
    ignore (entry_always#connect#toggled
      ~callback:(self#update (fun etask -> etask.Task.always_run <- entry_always#active)));
    ignore (entry_cmd#connect#changed
      ~callback:(self#update (fun etask -> etask.Task.cmd <- entry_cmd#text)));
    ignore (entry_args#connect#changed
      ~callback:(self#update (fun etask -> etask.Task.args <- (Cmd_line_args.parse entry_args#text))));
    ignore (entry_env#connect#changed
      ~callback:(self#update (fun etask -> etask.Task.env <- entry_env#entries)));
    ignore (entry_env#connect#replace_changed
      ~callback:(fun is_replace -> self#update (fun etask -> etask.Task.env_replace <- is_replace) ()));
    ignore (combo_phase#connect#changed
      ~callback:(self#update (fun etask -> etask.Task.phase <- Some (List.nth phases combo_phase#active))));
    ignore (button_dir#connect#changed
      ~callback:(self#update (fun etask -> etask.Task.dir <- button_dir#text)));

  method set et =
    etask <- Some et;
    entry_name#set_text et.Task.name;
    entry_always#set_active et.Task.always_run;
    entry_cmd#set_text et.Task.cmd;
    entry_args#set_text (Cmd_line_args.format et.Task.args);
    entry_env#set_entries et.Task.env;
    entry_env#set_replace et.Task.env_replace;
    button_dir#set_text et.Task.dir;
    match et.Task.phase with
      | Some ph -> combo_phase#set_active (Miscellanea.Xlist.pos ph phases);
      | None -> combo_phase#set_active 0;

  method private update update_func () =
    Gaux.may etask ~f:begin fun et ->
      update_func et;
      changed#call()
    end;

  method entry_name = entry_name

  method connect = new signals ~changed

end

and changed () = object (self) inherit [unit] signal () as super end
and signals ~changed =
object (self)
  inherit ml_signals [changed#disconnect]
  method changed = changed#connect ~after
end