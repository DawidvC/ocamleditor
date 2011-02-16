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
open Miscellanea

type t = {
  mutable id : int;
  mutable name : string;
  mutable default : bool;
  mutable byt : bool;
  mutable opt : bool;
  mutable libs : string;
  mutable other_objects : string;
  mutable files : string;
  mutable includes : string;
  mutable thread : bool;
  mutable vmthread : bool;
  mutable pp : string;
  mutable cflags : string;
  mutable lflags : string;
  mutable is_library : bool;
  mutable outname : string;
  mutable lib_install_path : string;
  mutable external_tasks : Task.t list;
} and rbt = [ `NONE | `CLEAN | `COMPILE | `REBUILD | `ETASK of Task.t ]

let default_runtime_build_task = `COMPILE

let string_of_rbt = function
  | `NONE -> "<NONE>"
  | `CLEAN -> "<CLEAN>"
  | `COMPILE -> "<COMPILE>"
  | `REBUILD -> "<REBUILD>"
  | `ETASK task -> task.Task.name

let markup_of_rbt = function
  | `NONE -> "None"
  | `CLEAN -> "Clean"
  | `COMPILE -> "Build"
  | `REBUILD -> "Rebuild <small><i>(Clean and Build)</i></small>"
  | `ETASK task -> Glib.Markup.escape_text task.Task.name

let rbt_of_string bconf = function
  | "<NONE>" -> `NONE
  | "<CLEAN>" -> `CLEAN
  | "<COMPILE>" -> `COMPILE
  | "<REBUILD>" -> `REBUILD
  | task_name -> begin
    try
      `ETASK (List.find (fun x -> x.Task.name = task_name) bconf.external_tasks)
    with Not_found -> default_runtime_build_task
  end

(** create *)
let create ~id ~name = {
  id = id;
  name = name;
  default = (id = 0);
  byt = true;
  opt = false;
  libs = "";
  other_objects = "";
  files = "";
  includes = "";
  thread = false;
  vmthread = false;
  pp = "";
  cflags = "";
  lflags = "";
  is_library = false;
  outname = "";
  lib_install_path = "";
  external_tasks = []
}

(** find_dependencies *)
let find_dependencies bconf = Dep.find (Miscellanea.split " +" bconf.files)

(** filter_external_tasks *)
let filter_external_tasks bconf phase =
  Miscellanea.Xlist.filter_map begin fun task ->
    match task.Task.phase with
    | Some ph ->
      if task.Task.always_run && phase = ph then Some (`OTHER, task) else None
    | _ -> None
  end bconf.external_tasks

(** create_cmd_line *)
let create_cmd_line ?(flags=[]) bconf =
  let quote = Filename.quote in
  let files = Cmd_line_args.parse bconf.files in
  Oe_config.oebuild_command,
  files
  @ ["-annot"]
  @ (if bconf.pp <> "" then ["-pp"; quote bconf.pp] else [])
  @ (if bconf.cflags <> "" then ["-cflags"; (quote bconf.cflags)] else [])
  @ (if bconf.lflags <> "" then ["-lflags"; (quote (bconf.lflags))] else [])
  @ (if bconf.includes <> "" then ["-I"; (quote (bconf.includes))] else [])
  @ (if bconf.libs <> "" then ["-l"; (quote (bconf.libs))] else [])
  @ (if bconf.other_objects <> "" then ["-m"; quote (bconf.other_objects)] else [])
  @ (if bconf.is_library then ["-a"] else [])
  @ (if bconf.byt then ["-byt"] else [])
  @ (if bconf.opt then ["-opt"] else [])
  @ (if bconf.thread then ["-thread"] else [])
  @ (if bconf.vmthread then ["-vmthread"] else [])
  @ (if bconf.outname <> "" then ["-o"; quote (bconf.outname)] else [])
  @ flags

(** tasks_compile *)
let tasks_compile ?(name="tasks_compile") ?(flags=[]) bconf =
  let filter_tasks = filter_external_tasks bconf in
  let et_before_compile = filter_tasks Task.Before_compile in
  let et_compile = filter_tasks Task.Compile in
  let et_compile = if et_compile = [] then [`COMPILE, begin
    let cmd, args = create_cmd_line ~flags bconf in
    Task.create ~name ~env:[] ~dir:"" ~cmd ~args ()
  end] else et_compile in
  let et_after_compile = filter_tasks Task.After_compile in
  (* Execute sequence *)
  et_before_compile @ et_compile @ et_after_compile

(** Convert from old file version *)
let convert_from_1 old_filename =
  let bconfigs = if Sys.file_exists old_filename then begin
    let ichan = open_in_bin old_filename in
    let (bconfigs : Bconf_old_1.t list) = input_value ichan in
    close_in ichan;
    List.rev bconfigs
  end else [] in
  (* write new file version *)
  let i = ref (-1) in
  let bconfigs = List.map begin fun t ->
    incr i;
    let target = create ~id:!i ~name:(string_of_int !i) in
    target.default <- (!i = 0);
    target.opt <- t.Bconf_old_1.opt;
    target.libs <- t.Bconf_old_1.libs;
    target.other_objects <- t.Bconf_old_1.mods;
    target.includes <- t.Bconf_old_1.includes;
    target.thread <- t.Bconf_old_1.thread;
    target.vmthread <- t.Bconf_old_1.vmthread;
    target.cflags <- t.Bconf_old_1.cflags;
    target.lflags <- t.Bconf_old_1.lflags;
    target.is_library <- (t.Bconf_old_1.libname <> None);
    target.outname <- "";
    target.lib_install_path <- "";
    target
  end bconfigs in
(*  if Sys.file_exists old_filename then (Sys.remove old_filename);*)
  bconfigs





























