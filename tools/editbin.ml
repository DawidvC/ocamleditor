(*

  This file is automatically generated by OCamlEditor 1.13.0, do not edit.

*)

let _ = if not Sys.win32 then exit 0

let _ = Printf.kprintf Sys.command "editbin %S /subsystem:windows 2>&1 1>NUL" Sys.argv.(1)
