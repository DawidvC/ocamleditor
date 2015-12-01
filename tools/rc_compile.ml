(*

  This file is automatically generated by OCamlEditor 1.13.3, do not edit.

*)

let is_mingw = try ignore (Sys.getenv "OCAMLEDITOR_MINGW"); true with Not_found -> false

let _ = if not Sys.win32 || is_mingw then exit 0;;

let resources = [
  "launcher", (".\\ocamleditorw.resource.rc", "\
101 ICON ocamleditor2.ico\n102 ICON ocamleditor.ico\n\n1 VERSIONINFO\n    FILEVERSION     1,13,2,0\n    PRODUCTVERSION  1,13,2,0\n    FILEOS          0x00000004L\n    FILETYPE        0x00000001L\n{\n    BLOCK \"StringFileInfo\"\n    {\n        BLOCK \"040904E4\"\n        {\n            VALUE \"CompanyName\", \"\\000\"\n            VALUE \"FileDescription\", \"OCamlEditor\\000\"\n            VALUE \"FileVersion\", \"1.13.2.0\\000\"\n            VALUE \"InternalName\", \"ocamleditorw.exe\\000\"\n            VALUE \"ProductName\", \"OCamlEditor\\000\"\n            VALUE \"LegalCopyright\", \"\\251 2014 Francesco Tovagliari\\000\"\n        }\n    }\n    BLOCK \"VarFileInfo\"\n    {\n      VALUE \"Translation\", 1033, 1252\n    }\n}\n");

  "ocamleditor-msvc", (".\\ocamleditor.opt.resource.rc", "\
101 ICON ocamleditor.ico\n\n1 VERSIONINFO\n    FILEVERSION     1,13,2,0\n    PRODUCTVERSION  1,13,2,0\n    FILEOS          0x00000004L\n    FILETYPE        0x00000001L\n{\n    BLOCK \"StringFileInfo\"\n    {\n        BLOCK \"040904E4\"\n        {\n            VALUE \"CompanyName\", \"\\000\"\n            VALUE \"FileDescription\", \"OCamlEditor\\000\"\n            VALUE \"FileVersion\", \"1.13.2.0\\000\"\n            VALUE \"InternalName\", \"ocamleditor.opt.exe\\000\"\n            VALUE \"ProductName\", \"OCamlEditor\\000\"\n            VALUE \"LegalCopyright\", \"\\251 2014 Francesco Tovagliari\\000\"\n        }\n    }\n    BLOCK \"VarFileInfo\"\n    {\n      VALUE \"Translation\", 1033, 1252\n    }\n}\n");

]

let _ = 
  let exit_code = Sys.command "where rc 1>NUL" in
  if exit_code <> 0 then failwith "Cannot find 'rc' command.";
  let exit_code = Sys.command "where cvtres 1>NUL" in
  if exit_code <> 0 then failwith "Cannot find 'cvtres' command.";
  let rcname, rc = List.assoc Sys.argv.(1) resources in
  let outchan = open_out_bin rcname in
  output_string outchan rc;
  close_out_noerr outchan;
  let exit_code = Sys.command ("rc /nologo " ^ rcname) in
  let exit_code = if exit_code = 0 then Sys.command ("cvtres /nologo /machine:x86 " ^ (Filename.chop_extension rcname) ^ ".res") else exit_code in
  if Sys.file_exists rcname then Sys.remove rcname;
  let name = (Filename.chop_extension rcname) ^ ".res" in
  if Sys.file_exists name then Sys.remove name;
  exit exit_code;
