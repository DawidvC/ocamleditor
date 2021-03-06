(*

  This file is automatically generated by OCamlEditor 1.13.4, do not edit.

*)

#load "unix.cma"

let get_command_output command =
  let ch = Unix.open_process_in command in
  set_binary_mode_in ch false;
  let output = ref [] in
  try
    while true do output := (input_line ch) :: !output done;
    assert false
  with End_of_file -> begin
    ignore (Unix.close_process_in ch);
    List.rev !output
  end | e -> begin
    ignore (Unix.close_process_in ch);
    raise e
  end

let is_mingw = List.exists ((=) "system: mingw") (get_command_output "ocamlc -config")

let _ = if not Sys.win32 || is_mingw then exit 0

let _ = Printf.kprintf Sys.command "editbin %S /subsystem:windows 2>&1 1>NUL" Sys.argv.(1)
