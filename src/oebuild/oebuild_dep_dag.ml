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

open Oebuild_util
open Printf

type t = (string, string list) Hashtbl.t

type dag_option = Dag of t | Cycle of string list

exception Cycle_exception of string list

(** array_exists *)
let array_exists from p a =
  try for i = from to Array.length a - 1 do
    if p a.(i) then raise Exit
  done; false with Exit -> true

(** reduce *)
let reduce : t -> unit = function table ->
  let rec (<-?-) x y =
    let deps = try Hashtbl.find table y with Not_found -> [] in
    (List.mem x deps) || (List.exists ((<-?-) x) deps)
  in
  let is_descendant = (*Miscellanea.Memo.create2*) (<-?-) in
  let reduce ll =
    let stop = ref "" in
    let rec reduce' ll =
      let len = Array.length ll in
      if len <= 1 then ll
      else
        let fst = ll.(0) in
        if fst = !stop then ll
        else begin
          let len = len - 1 in
          if array_exists 1 (is_descendant fst) ll
          then begin
            let tail = Array.make len "" in
            Array.blit ll 1 tail 0 len;
            reduce' tail
          end else begin
            if !stop = "" then (stop := fst);
            Array.blit ll 1 ll 0 len;
            ll.(len) <- fst;
            reduce' ll
          end
        end
    in
    Array.to_list (reduce' (Array.of_list ll))
  in
  Hashtbl.iter (fun key deps -> Hashtbl.replace table key (reduce deps)) table
;;

(** dot_of_dag *)
let dot_of_dag (dag : t) =
  let buf = Buffer.create 1000 in
  Buffer.add_string buf "digraph {\n";
  Hashtbl.iter begin fun key ->
    List.iter (kprintf (Buffer.add_string buf) "%S -> %S;\n" key)
  end dag;
  Buffer.add_string buf "}\n";
  Buffer.contents buf;;

(*(** has_cycle *)
let has_cycle ~ocamldeps ~toplevel_modules =
  (*try*)
    let rec find path node =
      if List.mem node path then raise (Cycle_exception (List.rev (node :: path)))
      else begin
        let children = try Hashtbl.find ocamldeps node with Not_found -> [] in
        List.iter (find (node :: path)) children
      end
    in
    List.iter (find []) toplevel_modules;
    (*None
  with Cycle_exception cycle -> Some cycle*)
;;*)

(** find_toplevels *)
let find_toplevels ocamldeps =
  let all_deps =
    Hashtbl.fold begin fun key deps acc ->
      Printf.printf "OCAMLDEPS: %-30s -> [%s]\n%!" key (String.concat ", " deps);
      List.rev_append deps acc
    end ocamldeps []
  in
  let toplevels =
    Hashtbl.fold begin fun key _ acc ->
      if List.mem key all_deps then acc else key :: acc
    end ocamldeps [];
  in
  Printf.printf "toplevels: %s\n%!" (String.concat ", " toplevels);
  toplevels
;;

(** create_dag *)
let create_dag ?times ~toplevel_modules () =
  let dirs = List.map Filename.dirname toplevel_modules in
  let dirs = List.filter ((<>) ".") dirs in
  let dirs = remove_dupl dirs in
  let search_path = List.map Ocaml_config.expand_includes dirs in
  let search_path = String.concat " " search_path in
  let filenames = List.map (fun dir -> sprintf "%s/*.mli %s/*.ml" dir dir) dirs in
  let filenames = (String.concat " " filenames) ^ " *.ml *.mli" in
  let ocamldeps = crono ~label:"ocamldep" (Oebuild_dep.ocamldep ?times ~search_path) filenames in
  try
    let table = Hashtbl.create 17 in
    let rec add path node =
      if List.mem node path then raise (Cycle_exception (node :: path))
      else begin
        let children = try Hashtbl.find ocamldeps node with Not_found -> [] in
        Printf.printf "DAG: %-30s : [%s]\n%!" node (String.concat ", " children);
        Hashtbl.replace table node children;
        List.iter (add (node :: path)) children
      end
    in
    let toplevel_modules_cmx =
      List.map (fun filename -> (Filename.chop_extension filename) ^ ".cmx") toplevel_modules
    in
    let need_find_tl = List.exists (fun tl -> not (Hashtbl.mem ocamldeps tl)) toplevel_modules_cmx in
    let toplevel_modules_cmx = if need_find_tl then find_toplevels ocamldeps else toplevel_modules_cmx in
    crono ~label:"add" (List.iter (add [])) toplevel_modules_cmx;
    crono ~label:"reduce" reduce table;
    Dag (table : t)
  with Cycle_exception cycle ->
    match cycle with
      | hd :: _ ->
        let cycle =
          let found = ref false in
          List.filter begin fun x ->
            found := !found || x = hd;
            !found
          end (List.rev cycle)
        in
        Cycle (List.rev cycle)
      | [] -> assert false
;;

