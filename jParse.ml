(*
 *  This file is part of JavaLib
 *  Copyright (c)2004 Nicolas Cannasse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)

(* file modified by eandre@irisa.fr 2006/03/23 *)

(* added by eandre@irisa.fr 23/03/2006 *)
open JClass
open IO.BigEndian
open ExtList
open ExtString
include JConsts

type tmp_constant =
	| ConstantClass of int
	| ConstantField of int * int
	| ConstantMethod of int * int
	| ConstantInterfaceMethod of int * int
	| ConstantString of int
	| ConstantInt of int32
	| ConstantFloat of float
	| ConstantLong of int64
	| ConstantDouble of float
	| ConstantNameAndType of int * int
	| ConstantStringUTF8 of string
	| ConstantUnusable

let parse_constant max ch =
	let cid = IO.read_byte ch in
	let error() = error ("Invalid constant " ^ string_of_int cid) in
	let index() =
		let n = read_ui16 ch in
		if n = 0 || n >= max then error();		
		n
	in
	match cid with
	| 7 ->
		ConstantClass (index())
	| 9 ->
		let n1 = index() in
		let n2 = index() in
		ConstantField (n1,n2)
	| 10 ->
		let n1 = index() in
		let n2 = index() in
		ConstantMethod (n1,n2)
	| 11 ->
		let n1 = index() in
		let n2 = index() in
		ConstantInterfaceMethod (n1,n2)
	| 8 ->
		ConstantString (index())
	| 3 ->		
		ConstantInt (read_real_i32 ch)
	| 4 ->
		let f = Int32.float_of_bits (read_real_i32 ch) in		
		ConstantFloat f
	| 5 ->
		ConstantLong (read_i64 ch)
	| 6 ->
		ConstantDouble (read_double ch)
	| 12 ->
		let n1 = index() in
		let n2 = index() in
		ConstantNameAndType (n1,n2)
	| 1 ->
		let len = read_ui16 ch in
		let str = IO.nread ch len in
		ConstantStringUTF8 str
	| n -> 
		error()

let parse_access_flags ch =
	let all_flags = [
	  AccPublic; AccPrivate; AccProtected; AccStatic;
	  AccFinal; AccSynchronized; AccVolatile; AccTransient;
	  AccNative; AccInterface; AccAbstract; AccStrict;
	  AccRFU 1; AccRFU 2; AccRFU 3; AccRFU 4 ] in
	let fl = read_ui16 ch in	
	let flags = ref [] in
	let fbit = ref 0 in
	List.iter (fun f ->
		if fl land (1 lsl !fbit) <> 0 then flags := f :: !flags;
		incr fbit
	) all_flags;
(* I don't know what it means, but this doesn't work when parsing runtime classes. Tifn
	if fl land (0x10000 - (1 lsl (succ !fbit))) <> 0 then error ("Invalid access flags " ^ string_of_int fl);
*)
	!flags

(* Validate an utf8 string and return a stream of characters. *)
let read_utf8 s =
  UTF8.validate s;
  let index = ref 0 in
    Stream.from
      (function _ ->
	 if UTF8.out_of_range s ! index
	 then None
	 else
	   let c = UTF8.look s ! index in
	     index := UTF8.next s ! index;
	     Some c)

(* Java ident, with unicode letter and numbers, starting with a letter. *)
let rec parse_ident buff = parser
  | [< 'c when c <> UChar.of_char ';'
	 && c <> UChar.of_char '/'; (* should be a letter *)
       name =
	 (UTF8.Buf.add_char buff c;
	  parse_more_ident buff) >] -> name

and parse_more_ident buff = parser
  | [< 'c when c <> UChar.of_char ';'
	 && c <> UChar.of_char '/'; (* should be a letter or a number *)
       name =
	 (UTF8.Buf.add_char buff c;
	  parse_more_ident buff) >] -> name
  | [< >] ->
      UTF8.Buf.contents buff

(* Qualified name (internally encoded with '/'). *)
let rec parse_name = parser
  | [< ident = parse_ident (UTF8.Buf.create 0);
       name = parse_more_name >] -> ident :: name

and parse_more_name = parser
  | [< 'slash when slash = UChar.of_char '/';
       name = parse_name >] -> name
  | [< >] -> []

(* Java type. *)
let rec parse_type = parser
  | [< 'b when b = UChar.of_char 'B' >] -> TByte
  | [< 'c when c = UChar.of_char 'C' >] -> TChar
  | [< 'd when d = UChar.of_char 'D' >] -> TDouble
  | [< 'f when f = UChar.of_char 'F' >] -> TFloat
  | [< 'i when i = UChar.of_char 'I' >] -> TInt
  | [< 'j when j = UChar.of_char 'J' >] -> TLong
  | [< 's when s = UChar.of_char 'S' >] -> TShort
  | [< 'z when z = UChar.of_char 'Z' >] -> TBool

  | [< 'l when l = UChar.of_char 'L';
       name = parse_name;
       'semicolon when semicolon = UChar.of_char ';' >] -> TObject name

  | [< a = parse_array >] -> a

(* Java array type. *)
and parse_array = parser
  | [< 'lbracket when lbracket = UChar.of_char '['; typ = parse_type >] ->
      TArray (typ, None)

let rec parse_types = parser
  | [< typ = parse_type ; types = parse_types >] -> typ :: types
  | [< >] -> []

let parse_type_option = parser
  | [< typ = parse_type >] -> Some typ
  | [< >] -> None

(* A class name, possibly an array class. *)
let parse_ot = parser
  | [< array = parse_array >] -> array
  | [< name = parse_name >] -> TObject name

let parse_method_sig = parser
  | [< 'lpar when lpar = UChar.of_char '(';
       types = parse_types;
       'rpar when rpar = UChar.of_char ')';
       typ = parse_type_option >] ->
      (types, typ)

(* Java signature. *)
let rec parse_sig = parser
    (* We cannot delete that because of "NameAndType" constants. *)
  | [< typ = parse_type >] -> SValue typ
  | [< sign = parse_method_sig >] -> SMethod sign

let parse_objectType s =
  try
    parse_ot (read_utf8 s)
  with
      Stream.Failure -> failwith ("invalid object type " ^ s)

let parse_type s =
  try
    parse_type (read_utf8 s)
  with
      Stream.Failure -> failwith ("invalid type " ^ s)

let parse_method_signature s =
  try
    parse_method_sig (read_utf8 s)
  with
      Stream.Failure -> error ("Invalid method signature " ^ s)

let parse_signature s =
  try
    parse_sig (read_utf8 s)
  with
      Stream.Failure -> error ("Invalid signature " ^ s)

let parse_stackmap_frame consts ch =
	let parse_type_info ch = match IO.read_byte ch with
		| 0 -> VTop
		| 1 -> VInteger
		| 2 -> VFloat
		| 3 -> VDouble
		| 4 -> VLong
		| 5 -> VNull
		| 6 -> VUninitializedThis
		| 7 -> VObject (get_signature consts ch)
		| 8 -> VUninitialized (read_ui16 ch)
		| n -> prerr_endline ("type = " ^ string_of_int n); raise Exit
	in let parse_type_info_array ch nb_item =
		try
			List.init nb_item (fun _ ->parse_type_info ch)
		with 
			Exit -> error "Invalid type in StackMap"
	in let offset = read_ui16 ch in
	let number_of_locals = read_ui16 ch in
	let locals = parse_type_info_array ch number_of_locals in
	let number_of_stack_items = read_ui16 ch in
	let stack = parse_type_info_array ch number_of_stack_items in
	(offset,locals,stack)

let rec parse_code consts ch =
	let max_stack = read_ui16 ch in
	let max_locals = read_ui16 ch in
	let clen = read_i32 ch in
	let code = 
		(try			
			JCode.parse_code ch consts clen
		with
			JCode.Invalid_opcode n -> error ("Invalid opcode " ^ string_of_int n))
	in
	let exc_tbl_length = read_ui16 ch in
	let exc_tbl = List.init exc_tbl_length (fun _ ->
		let spc = read_ui16 ch in
		let epc = read_ui16 ch in
		let hpc = read_ui16 ch in
		let ct =
		  match read_ui16 ch with
		    | 0 -> None
		    | ct ->
			match get_constant consts ct with
			  | ConstClass (TObject c) -> Some c
			  | _ -> error "Invalid class index"
		in
		{
			e_start = spc;
			e_end = epc;
			e_handler = hpc;
			e_catch_type = ct;
		}
	) in
	let attrib_count = read_ui16 ch in
	let attribs = List.init attrib_count (fun _ -> parse_attribute consts ch) in
	{
		c_max_stack = max_stack;
		c_max_locals = max_locals;
		c_exc_tbl = exc_tbl;
		c_attributes = attribs;
		c_code = code;
	}

and parse_attribute consts ch =
	let aname = get_string consts ch in
	let error() = error ("Malformed attribute " ^ aname) in
	let alen = read_i32 ch in
	match aname with
	| "SourceFile" ->
		if alen <> 2 then error();
		AttributeSourceFile (get_string consts ch)
	| "ConstantValue" ->
		if alen <> 2 then error();
		AttributeConstant (get_constant consts (read_ui16 ch))
	| "Code" ->
		(* correct length not checked *)
		AttributeCode (parse_code consts ch)
	| "LineNumberTable" ->
		let nentry = read_ui16 ch in
		if nentry * 4 + 2 <> alen then error();
		AttributeLineNumberTable (List.init nentry (fun _ -> let pc = read_ui16 ch in let line = read_ui16 ch in pc , line)) 
	| "StackMap" ->
		let nb_stackmap_frames = read_ui16 ch in
		AttributeStackMap (List.init nb_stackmap_frames (fun _ -> parse_stackmap_frame consts ch ))
	| _ ->
(* Too verbose. Tifn
		Printf.printf "Unknown attribute %s\n" aname;
*)
		AttributeUnknown (aname,IO.nread ch alen)

let parse_field consts ch =
	let acc = parse_access_flags ch in
	let name = get_string consts ch in
	let sign = parse_type (get_string consts ch) in
	let attrib_count = read_ui16 ch in
	let attribs = List.init attrib_count (fun _ -> parse_attribute consts ch) in
	{
		f_name = name;
		f_signature = sign;
		f_attributes = attribs;
		f_flags = acc;
	}

let parse_method consts ch =
	let acc = parse_access_flags ch in
	let name = get_string consts ch in
	let sign = parse_method_signature (get_string consts ch) in
	let attrib_count = read_ui16 ch in
	let code = ref None in
	let attribs = List.init attrib_count (fun _ -> 
		match parse_attribute consts ch with
		| AttributeCode c ->
			if !code <> None then error "Duplicate code";
			code := Some c;
			AttributeCode c
		| a ->
			a
	) in
	{
		m_name = name;
		m_signature = sign;
		m_attributes = attribs;
		m_code = !code;
		m_flags = acc;
	}

let rec expand_constant consts n =
	let expand cl nt =
		match expand_constant consts cl , expand_constant consts nt with
		| ConstClass c , ConstNameAndType (n,s) -> (c,n,s)
		| ConstClass _ , ConstNameAndType _ -> failwith "Class is not a class"
		| _ , _ -> failwith "Malformed Class or NameAndType Constant"
	in
	match consts.(n) with
	| ConstantClass i -> 
	    (match expand_constant consts i with
	       | ConstStringUTF8 s -> ConstClass (parse_objectType s)
	       | _ -> failwith "")
	| ConstantField (cl,nt) ->
	    (match expand cl nt with
	       | TObject c, n, SValue v -> ConstField (c, n, v)
	       | _, _, SMethod _ -> failwith "")
	| ConstantMethod (cl,nt) ->
	    (match expand cl nt with
	       | c, n, SMethod v -> ConstMethod (c, n, v)
	       | _, _, SValue _ -> failwith "")
	| ConstantInterfaceMethod (cl,nt) ->
	    (match expand cl nt with
	       | c, n, SMethod v -> ConstInterfaceMethod (c, n, v)
	       | _, _, SValue _ -> failwith "")
	| ConstantString i ->
		(match expand_constant consts i with
		| ConstStringUTF8 s -> ConstString s
		| _ -> failwith "Malformed String Constant")
	| ConstantInt i -> ConstInt i
	| ConstantFloat f -> ConstFloat f
	| ConstantLong l -> ConstLong l
	| ConstantDouble f -> ConstDouble f
	| ConstantNameAndType (n,t) ->
		(match expand_constant consts n , expand_constant consts t with
		| ConstStringUTF8 n , ConstStringUTF8 t -> ConstNameAndType (n,parse_signature t)
		| _ -> failwith "Malformed NameAndType Constant")
	| ConstantStringUTF8 s -> ConstStringUTF8 s
	| ConstantUnusable -> ConstUnusable

let parse_class ch =
	let magic = read_real_i32 ch in
	if magic <> 0xCAFEBABEl then error "Invalid header";
	let _version_minor = read_ui16 ch in
	let _version_major = read_ui16 ch in
	let constant_count = read_ui16 ch in
	let const_big = ref true in
	let consts = Array.init constant_count (fun _ -> 
		if !const_big then begin
			const_big := false;
			ConstantUnusable
		end else
			let c = parse_constant constant_count ch in
			(match c with ConstantLong _ | ConstantDouble _ -> const_big := true | _ -> ());
			c
	) in
	let consts = Array.mapi (fun i _ -> expand_constant consts i) consts in
	let flags = parse_access_flags ch in
	let this = get_class consts ch in
	let super_idx = read_ui16 ch in
	let super = (if super_idx = 0 then None else
		match get_constant consts super_idx with
		| ConstClass (TObject name) -> Some name
		| _ -> error "Invalid super index")
	in
	let interface_count = read_ui16 ch in
	let interfaces = List.init interface_count (fun _ -> get_class consts ch) in
	let field_count = read_ui16 ch in
	let fields = List.init field_count (fun _ -> parse_field consts ch) in
	let method_count = read_ui16 ch in
	let methods = List.init method_count (fun _ -> parse_method consts ch) in
	let attrib_count = read_ui16 ch in
	let attribs = List.init attrib_count (fun _ -> parse_attribute consts ch) in
	{
		j_consts = consts;
		j_flags = flags;
		j_name = this;
		j_super = super;
		j_interfaces = interfaces;
		j_fields = fields;
		j_methods = methods;
		j_attributes = attribs;
	}
