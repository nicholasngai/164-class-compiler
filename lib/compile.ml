open S_exp
open Asm

exception BadExpression of s_exp

let num_shift = 2
let num_mask = 0b11
let num_tag = 0b00

let bool_shift = 7
let bool_mask = 0b1111111
let bool_tag = 0b0011111

let operand_of_bool (b : bool) : operand =
  Imm (((if b then 1 else 0) lsl bool_shift) lor bool_tag)

let operand_of_num (x : int) : operand = Imm ((x lsl num_shift) lor num_tag)

let zf_to_bool : directive list =
  [ Mov (Reg Rax, Imm 0)
  ; Setz (Reg Rax)
  ; Shl (Reg Rax, Imm bool_shift)
  ; Or (Reg Rax, Imm bool_tag) ]

let rec compile_exp (exp : s_exp) : directive list =
  match exp with
  | Num n ->
      [Mov (Reg Rax, operand_of_num n)]
  | Sym "true" ->
      [Mov (Reg Rax, operand_of_bool true)]
  | Sym "false" ->
      [Mov (Reg Rax, operand_of_bool false)]
  | Lst [Sym "not"; arg] ->
      compile_exp arg @ [Cmp (Reg Rax, operand_of_bool false)] @ zf_to_bool
  | Lst [Sym "zero?"; arg] ->
      compile_exp arg @ [Cmp (Reg Rax, operand_of_num 0)] @ zf_to_bool
  | Lst [Sym "num?"; arg] ->
      compile_exp arg
      @ [And (Reg Rax, Imm num_mask); Cmp (Reg Rax, Imm num_tag)]
      @ zf_to_bool
  | Lst [Sym "add1"; arg] ->
      compile_exp arg @ [Add (Reg Rax, operand_of_num 1)]
  | Lst [Sym "sub1"; arg] ->
      compile_exp arg @ [Sub (Reg Rax, operand_of_num 1)]
  | Lst [Sym "if"; test_exp; then_exp; else_exp] ->
      let else_label = Util.gensym "else" in
      let continue_label = Util.gensym "continue" in
      compile_exp test_exp
      @ [Cmp (Reg Rax, operand_of_bool false); Jz else_label]
      @ compile_exp then_exp @ [Jmp continue_label] @ [Label else_label]
      @ compile_exp else_exp @ [Label continue_label]
  | e ->
      raise (BadExpression e)

let compile (program : s_exp) : string =
  [Global "entry"; Label "entry"] @ compile_exp program @ [Ret]
  |> List.map string_of_directive
  |> String.concat "\n"

let compile_to_file (program : string) : unit =
  let file = open_out "program.s" in
  output_string file (compile (parse program)) ;
  close_out file

let compile_and_run (program: string): string =
    compile_to_file program;
    let format = (if Asm.macos then "macho64" else "elf64") in
    ignore (Unix.system ("nasm program.s -f " ^ format ^ " -o program.o"));
    ignore (Unix.system "gcc program.o runtime.c -o program");
    let inp = Unix.open_process_in "./program" in
    let r = input_line inp in
    close_in inp; r

let difftest (examples : string list) =
  let results =
    List.map (fun ex -> (compile_and_run ex, Interp.interp ex)) examples
  in
  List.for_all (fun (r1, r2) -> r1 = r2) results

let test () =
  difftest
    [ "43"
    ; "5"
    ; "(add1 (sub1 4))"
    ; "(sub1 (sub1 1))"
    ; "(not 3)"
    ; "(not (not false))"
    ; "(not (zero? 4))"
    ; "(num? (add1 3))" ]

