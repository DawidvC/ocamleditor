(*

  OCamlEditor
  Copyright (C) 2010-2013 Francesco Tovagliari

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

module Dep_dag = Oebuild_dep_dag

type process_output = {
  command           : string;
  filename          : string;
  mutable exit_code : int;
  mutable err       : Buffer.t;
  mutable out       : Buffer.t;
}

module NODE = struct
  type key = string
  type t = {
    nd_create_command     : (string -> string option);
    nd_at_exit            : (process_output -> unit);
    nd_filename           : string;
    mutable nd_processing : bool;
  }
  let equal a b = a.nd_filename = b.nd_filename
  let hash x = Hashtbl.hash x.nd_filename
  let to_string x = x.nd_filename
end

module Dag = Oebuild_dag.Make(NODE)

type t = (NODE.key, Dag.entry) Hashtbl.t

type dag = {
  graph : t;
  mutex : Mutex.t;
}

(** print_results *)
let print_results errors messages =
  List.iter begin fun error ->
    Printf.eprintf "%s --- (exit code: %d)%s\n%s\n----------------------------------------------------------------------\n"
      error.command error.exit_code
      (if Buffer.length error.out > 0 then "\n" ^ Buffer.contents error.out else "")
      (Buffer.contents error.err);
  end errors;
  flush_all();
  List.iter begin fun message ->
    if Buffer.length message.out > 0 || Buffer.length message.err > 0 then
      Printf.printf "%s%s\n%s\n----------------------------------------------------------------------\n"
        message.command
        (if Buffer.length message.out > 0 then "\n" ^ Buffer.contents message.out else "")
        (Buffer.contents message.err);
  end messages;
  flush_all()
;;

(** create_dag *)
let create_dag ?times ~cb_create_command ~cb_at_exit ~toplevel_modules () =
  let open Dag in
  match Dep_dag.create_dag ?times ~toplevel_modules () with
    | Dep_dag.Cycle cycle -> kprintf failwith "Cycle: %s" (String.concat "->" cycle)
    | Dep_dag.Dag dag' ->
      let dag = Hashtbl.create 17 in
      Hashtbl.iter begin fun filename deps ->
        let node = {
          NODE.nd_create_command = cb_create_command;
          nd_at_exit        = cb_at_exit;
          nd_filename       = filename;
          nd_processing     = false
        } in
        Hashtbl.add dag filename {
          key          = filename;
          node         = node;
          dependencies = [];
          dependants   = []
        }
      end dag';
      Hashtbl.iter begin fun node deps ->
        try
          let node = Hashtbl.find dag node in
          List.iter begin fun dep ->
            let e = Hashtbl.find dag dep in
            node.dependencies <- e :: node.dependencies;
          end deps;
        with Not_found -> assert false
      end dag';
      set_dependants dag;
      { graph = dag; mutex = Mutex.create() }
;;

(** create_process *)
let create_process cb_create_command cb_at_exit dag leaf errors messages =
  leaf.Dag.node.NODE.nd_processing <- true;
  let filename = Oebuild_util.replace_extension leaf.Dag.node.NODE.nd_filename in
  let command = cb_create_command filename in
  match command with
    | Some command ->
      Printf.printf "create_process: %s\n%!" command;
      let output = {
        command;
        filename;
        exit_code  = 0;
        err        = Buffer.create 10;
        out        = Buffer.create 10
      } in
      let at_exit exit_code =
        output.exit_code <- exit_code;
        if exit_code <> 0 then (errors := output :: !errors)
        else messages := output :: !messages;
        Mutex.lock dag.mutex;
        Dag.remove_leaf dag.graph leaf;
        Mutex.unlock dag.mutex;
        cb_at_exit output
      in
      let process_in stdin = Buffer.add_string output.out (input_line stdin) in
      let process_err stderr = Buffer.add_string output.err (input_line stderr) in
      Oebuild_util.exec ~verbose:false ~join:false ~at_exit ~process_in ~process_err command
    | _ ->
      Printf.printf "create_process: %30s (No command)\n%!" filename;
      Mutex.lock dag.mutex;
      Dag.remove_leaf dag.graph leaf;
      Mutex.unlock dag.mutex;
      None
;;

(** process_parallel *)
let process_parallel dag =
  let open NODE in
  let errors = ref [] in
  let messages = ref [] in
  let process_time = Unix.gettimeofday () in
  let leaves = ref [] in
  begin
    try
      while
        leaves := Dag.get_leaves dag.graph;
        !leaves <> []
      do
        List.iter begin fun leaf ->
          if not leaf.Dag.node.nd_processing
          then (create_process
                  leaf.Dag.node.nd_create_command
                  leaf.Dag.node.nd_at_exit
                  dag leaf errors messages |> ignore)
        end !leaves;
        (* Errors occurred at the same level (leaves) are independent so
           checking for the presence of errors after looping over the leaves
           can collect more than one of these independent errors (although
           there is no guarantee they are all). *)
        if !errors <> [] then raise Exit;
        Thread.delay 0.005;
      done;
    with Exit -> ()
  end;
  let errors = List.rev !errors in
  let messages = List.rev !messages in
  let process_time = Unix.gettimeofday () -. process_time in
  print_results errors messages;
  process_time
;;




