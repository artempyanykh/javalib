(*
 *  This file is part of JavaLib
 *  Copyright (c)2007 Université de Rennes 1 / CNRS
 *  Tiphaine Turpin <first.last@irisa.fr>
 *  Laurent Hubert <first.last@irisa.fr>
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

open JDumpBasics
open JBasics
open JClass
open Format

type info = {
  (* printing functions *)
  (* those printing function must print a cut at the begining of their output*)
  p_global : formatter -> unit;
  p_class: class_name -> formatter -> unit;
  p_field: class_name -> field_signature -> formatter -> unit;
  p_method: class_name -> method_signature -> formatter -> unit;
  p_pp: class_name -> method_signature -> int -> formatter -> unit;

  (* filtering functions (e.g. to avoid printing methods that are never called) *)
  f_class: class_name -> bool;
  f_field: class_name -> field_signature -> bool;
  f_method: class_name -> method_signature -> bool;
}

let void_info = {
  p_global = (fun _fmt -> ());
  p_class= (fun _cn _fmt -> ());
  p_field = (fun _cn _fs _fmt -> ());
  p_method = (fun _cn _ms _fmt -> ());
  p_pp = (fun _cn _ms _i _fmt -> ());
  f_class = (fun _cn -> true);
  f_field = (fun _cn _fs -> true);
  f_method = (fun _cn _ms -> true);
}

let replace_all ~str ~sub ~by =
  let continue = ref true
  and s = ref str
  and i = ref 0 in
    while !continue do
      let (c,str) = ExtString.String.replace ~str:!s ~sub ~by in
	s := str;
	continue := c;
	incr i
    done;
    (!i,!s)

let type2shortstring t = 
  let bt2ss = function
    | `Long -> "J"
    | `Float -> "F"
    | `Double -> "D"
    | `Int -> "I"
    | `Short -> "S"
    | `Char -> "C"
    | `Byte -> "B"
    | `Bool -> "Z"
  in
  let rec ot2ss = function
    | TClass cn -> "L"^JDumpBasics.class_name cn^";"
    | TArray t -> "["^ vt2ss t
  and vt2ss = function
    | TBasic t -> bt2ss t
    | TObject t -> ot2ss t
  in vt2ss t

let rettype2shortstring = function
  | None -> "V"
  | Some t -> type2shortstring t

let fs2anchortext (cn,fs) =
  JDumpBasics.class_name cn^fs.fs_name^":"^type2shortstring fs.fs_type

let ms2anchortext (cn,ms) =
  let str = snd (replace_all ~str:ms.ms_name ~sub:"<" ~by:"-") in
  let str = snd (replace_all ~str ~sub:">" ~by:"-") in
    JDumpBasics.class_name cn^str^"("
    ^ String.concat "" (List.map type2shortstring ms.ms_parameters)
    ^")"^rettype2shortstring ms.ms_return_type

let ss2anchor s fmt =
  fprintf fmt "@{<html>@<0>%s@}" ("<a name=\"" ^ s ^ "\" />")
let cn2anchor cn = ss2anchor (JDumpBasics.class_name cn)
let fs2anchor (cn,fs) = ss2anchor (fs2anchortext (cn,fs))
let ms2anchor (cn,ms) = ss2anchor (ms2anchortext (cn,ms))

let ss2link s fmt text =
  fprintf fmt "@{<html>@<0>%s@}%s@{<html>@<0>%s@}" ("<a href=\"" ^ s ^ "\">") text "</a>"
let cn2link cn = ss2link ("#"^JDumpBasics.class_name cn)
let fs2link (cn,fs) = ss2link ("#"^fs2anchortext (cn,fs))
let ms2link (cn,ms) = ss2link ("#"^ms2anchortext (cn,ms))
  
let access2string = function
  | `Public -> "public "
  | `Default -> ""
  | `Private -> "private "
  | `Protected -> "protected "

let final2string = function
  | false -> ""
  | true -> "final "

let static2string = function
  | false -> ""
  | true -> "static "

let kind2string = function
  | NotFinal -> ""
  | Final -> "final "
  | Volatile -> "volatile "

let cstvalue2string = function
  | ConstString s -> "\""^s^"\""
  | ConstInt i -> Printf.sprintf "%ld" i
  | ConstFloat f -> Printf.sprintf "%ff" f
  | ConstLong l -> Printf.sprintf "%LdL" l
  | ConstDouble d -> Printf.sprintf "%fF" d
  | ConstClass cl -> Printf.sprintf "%s" (JDumpBasics.object_value_signature cl)

let pp_source fmt = function
  | None -> ()
  | Some s -> fprintf fmt "@[compiled@ from@ file@ %s@]@," s

let rec pp_cinterfaces fmt = function
  | i::others -> fprintf fmt "%a@ %a" (cn2link i) (class_name i) pp_cinterfaces others
  | [] -> ()

let pp_inner_classes fmt icl =
  let ic_type2string = function
    | `ConcreteClass -> "class "
    | `Abstract -> "abstract class "
    | `Interface -> "interface "
  and ic_cn fmt = function (*source_name,class_name*)
    | (None,None) -> ()
    | (Some cn_source,Some cn)  ->
	fprintf fmt "%s =@ class %s " cn_source (class_name cn)
    | (Some scn,None) -> fprintf fmt "%s " scn
    | (None, Some cn) -> fprintf fmt "%s " (class_name cn)
  and ic_ocn fmt = function
    | None -> ()
    | Some cn -> fprintf fmt "of class %s" (class_name cn)
  in
  let pp_ic fmt ic =
    fprintf fmt "@[%s%s%s%s%a%a@]"
      (access2string ic.ic_access)
      (static2string ic.ic_static)
      (final2string ic.ic_final)
      (ic_type2string ic.ic_type)
      ic_cn (ic.ic_source_name,ic.ic_class_name)
      ic_ocn ic.ic_outer_class_name
  in
    match icl with
      | [] -> ()
      | _ ->
	  fprintf fmt "@[<v 2>inner classes:@,";
	  List.iter (pp_ic fmt) icl;
	  fprintf fmt "@]@,"

let pp_concat f pp_open pp_close pp_sep = function
  | [] -> ()
  | a::[] -> pp_open (); f a;pp_close ();
  | a::l ->
      pp_open ();
      f a;
      List.iter (fun a -> pp_sep ();f a) l;
      pp_close ()
     
let pp_other_attr fmt pp_open pp_close pp_sep attrl =
pp_concat
  (fun (name,content) ->
    fprintf fmt "@[Unknown attribute:@ %s@ (%s)@]" name content)
  pp_open
  pp_close
  pp_sep
  attrl

let pp_attributes fmt pp_open pp_close pp_sep attributes =
  if (attributes.synthetic || attributes.deprecated || List.length attributes.other > 0)
  then
    begin
      pp_open ();
      if attributes.deprecated then
	(pp_print_string fmt "AttributeDeprecated");
      if attributes.deprecated && (attributes.synthetic || List.length attributes.other > 0)
      then pp_sep ();
      if attributes.synthetic then
	(pp_print_string fmt "AttributeSynthetic");
      if attributes.synthetic && List.length attributes.other > 0
      then pp_sep ();
      pp_other_attr fmt ignore ignore pp_sep attributes.other;
      pp_close ();
    end

(* this function does not finish with a cut or a space *)
let rec pp_object_type fmt = function
  | TClass cl -> fprintf fmt "%s" (class_name cl)
  | TArray s -> fprintf fmt "%a[]" pp_value_type s
and pp_value_type fmt = function
  | TBasic t -> fprintf fmt "%s" (JDumpBasics.basic_type t)
  | TObject o -> fprintf fmt "%a" pp_object_type o

(* this function does not finish with a cut or a space *)
let pp_field_signature fmt fs =
  fprintf fmt "%a@ %s" pp_value_type fs.fs_type fs.fs_name

let pp_method_signature fmt ms =
  begin
    match ms.ms_return_type with
      | None -> fprintf fmt "void@ "
      | Some v -> fprintf fmt "%a@ " pp_value_type v
  end;
  fprintf fmt "%s(@[<2>" ms.ms_name;
  begin
    match ms.ms_parameters with
      | [] -> ()
      | p::[] -> pp_value_type fmt p
      | p::pl ->
	  pp_value_type fmt p;
	  List.iter  (fun p -> fprintf fmt ",@ "; pp_value_type fmt p) pl
  end;
  fprintf fmt "@])"

let pp_exceptions fmt = function
  | [] -> ()
  | e::[] -> fprintf fmt "@[<2>throws %s@]@ " (class_name e)
  | e::el ->
      fprintf fmt "@[<2>throws %s" (class_name e);
      List.iter (fun e -> fprintf fmt ",@ %s" (class_name e)) el;
      fprintf fmt "@]@ "

let pp_opcode fmt =
  let ppfs fmt (cn,fs) =
    fs2link
      (cn,fs) fmt
      (sprintf "%s.%s:%s" (class_name cn) fs.fs_name (value_signature fs.fs_type))
  and ppms fmt (cn,ms) =
    ms2link
      (cn,ms) fmt
      (sprintf "%s.%s:%s"
	  (class_name cn)
	  ms.ms_name
	  (method_signature "" (ms.ms_parameters,ms.ms_return_type)))
  in function
    | OpGetStatic (cn,fs) ->
	fprintf fmt "getstatic %a" ppfs (cn,fs)
    | OpPutStatic (cn,fs) -> fprintf fmt "putstatic %a" ppfs (cn,fs)
    | OpPutField (cn,fs) -> fprintf fmt "putfield %a" ppfs (cn,fs)
    | OpGetField (cn,fs) -> fprintf fmt "getfield %a" ppfs (cn,fs)
    | OpInvoke (x, ms) ->
	(match x with
	  | `Virtual (TClass cn) -> fprintf fmt "invokevirtual %a" ppms (cn,ms)
	  | `Virtual (TArray _) -> 
	      fprintf fmt "invokevirtual [array].%s:%s" ms.ms_name
		(method_signature "" (ms.ms_parameters,ms.ms_return_type))
	  | `Special c -> fprintf fmt "invokespecial %a" ppms (c,ms)
	  | `Static c -> fprintf fmt "invokestatic %a" ppms (c,ms)
	  | `Interface c -> fprintf fmt "invokeinterface %a" ppms (c,ms))
    | other -> pp_print_string fmt (JDump.opcode other)


let pp_code cn ms info fmt code =
  let hasinfo i = 
    Buffer.reset stdbuf;
    assert(Buffer.contents stdbuf = "");
    info.p_pp cn ms i str_formatter;
    String.length (flush_str_formatter ()) <> 0
  and pp_inst = info.p_pp cn ms
  in
    Array.iteri
      (fun i -> function
	| OpInvalid -> ()
	| op ->
	    if hasinfo i then fprintf fmt "    @[%t@]@," (pp_inst i);
	    fprintf fmt "@[<4>%3d: %a@]@,"  i pp_opcode op
      )
      code

let pp_line_number_table fmt = function
  | None -> ()
  | Some lnt ->
      pp_concat
	(fun (pc,line) -> fprintf fmt "@[line %2d:%2d @]" line pc)
	(fun _ -> fprintf fmt "@,@[<v 2>Line Number Table:@,")
	(fun _ -> fprintf fmt "@]")
	(fun _ -> fprintf fmt "@,")
	lnt

let pp_local_variable_table fmt = function
  | None -> ()
  | Some lvt ->
      pp_concat
	(fun (start,len,name,sign,index) ->
	  fprintf fmt "@[<2>[%2d,%2d]: %d is %a %s@]"
	    start (start+len) index pp_value_type sign name)
	(fun _ -> fprintf fmt "@,@[<v 2>Local Variable Table:@,")
	(fun _ -> fprintf fmt "@]")
	(fun _ -> fprintf fmt "@,")
	lvt

let pp_stack_map fmt = function
  | None -> ()
  | Some sm ->
      let pp_verif_info fmt = function
	| VTop -> fprintf fmt "Top"
	| VInteger -> fprintf fmt "Integer"
	| VFloat -> fprintf fmt "Float"
	| VDouble -> fprintf fmt "Double"
	| VLong -> fprintf fmt "Long"
	| VNull -> fprintf fmt "Null"
	| VUninitializedThis -> fprintf fmt "UninitializedThis"
	| VObject c -> fprintf fmt "Object %a" pp_object_type c
	| VUninitialized off -> fprintf fmt "Uninitialized %d" off
      in
      let pp_line fmt (offset,locals,stack) =
	fprintf fmt "@[<hv 2>offset=%2d,@ locals=[" offset;
	pp_concat
	  (pp_verif_info fmt)
	  (fun _ -> fprintf fmt "@[")
	  (fun _ -> fprintf fmt "@]")
	  (fun _ -> fprintf fmt ";@ ")
	  locals;
	fprintf fmt "],@ stack=[";
	pp_concat
	  (pp_verif_info fmt)
	  (fun _ -> fprintf fmt "@[")
	  (fun _ -> fprintf fmt "@]")
	  (fun _ -> fprintf fmt ";@ ")
	  stack;
	fprintf fmt "]@]"
      in
      pp_concat
	(fun line -> pp_line fmt line)
	(fun _ -> fprintf fmt "@,@[<v 2>Stack Map:@,")
	(fun _ -> fprintf fmt "@]")
	(fun _ -> fprintf fmt "@,")
	sm

let pp_exc_tbl fmt exc_tbl =
  let catch_type = function
    | None -> "All"
    | Some cn -> class_name cn
  in
  pp_concat
    (fun e ->
      fprintf fmt
	"@[[%d,%d) -> %d : catch %s@]"
	e.e_start e.e_end e.e_handler (catch_type e.e_catch_type))
    (fun _ -> fprintf fmt "@,@[<v 2>Exception handlers:@,")
    (fun _ -> fprintf fmt "@]")
    (fun _ -> fprintf fmt "@,")
    exc_tbl

let pp_implementation cn ms info fmt c =
  let nb_loc fmt = fprintf fmt "Locals=%d" c.c_max_locals
  and nb_stack fmt = fprintf fmt "Stack=%d" c.c_max_stack
  and code fmt = pp_code cn ms info fmt c.c_code
  and exc_tbl fmt = pp_exc_tbl fmt c.c_exc_tbl
  and lnt fmt = pp_line_number_table fmt c.c_line_number_table
  and lvt fmt = pp_local_variable_table fmt c.c_local_variable_table
  and sm fmt = pp_stack_map fmt c.c_stack_map
  and att fmt = pp_other_attr fmt ignore ignore (fun _ -> fprintf fmt "@,") c.c_attributes
  in
    fprintf fmt
      "@[<v>@[%t,@ %t@]@,%t{@[<v>%t@]}%t%t%t%t@]@,"
      nb_stack nb_loc att code exc_tbl lvt lnt sm

let pp_cmethod cn info fmt m =
  if info.f_method cn m.cm_signature then
  let sign fmt = pp_method_signature fmt m.cm_signature
  and anchor fmt = ms2anchor (cn,m.cm_signature) fmt
  and static = static2string m.cm_static
  and final = final2string m.cm_final
  and synchro = (if m.cm_synchronized then "synchronized " else "")
  and strict = (if m.cm_strict then "strict " else "")
  and access = access2string m.cm_access
  and exceptions fmt = pp_exceptions fmt m.cm_exceptions
  and att fmt =
    pp_attributes fmt
      (fun _ -> fprintf fmt "@[<v>")
      (fun _ -> fprintf fmt "@]@,")
      (fun _ -> fprintf fmt "@,")
      m.cm_attributes
  in
    match m.cm_implementation with
      | Native ->
	  fprintf fmt "@[<v 2>%t@[<3>%s@,%s@,%s@,native@ %s@,%s@,%t@ %t@]@,%t%t@]"
	    anchor access static final synchro strict sign exceptions
	    (info.p_method cn m.cm_signature) att
      | Java code ->
	  let implem fmt = pp_implementation cn m.cm_signature info fmt code
	  in
	    fprintf fmt "@[<v 2>%t@[<3>%s@,%s@,%s@,%s@,%s@,%t@ %t@]{@{<method>@,%t%t%t@}}@]"
	      anchor access static final synchro strict sign exceptions
	      (info.p_method cn m.cm_signature) att implem

let pp_amethod cn info fmt m =
  if info.f_method cn m.am_signature then
  let sign fmt = pp_method_signature fmt m.am_signature
  and anchor fmt = ms2anchor (cn,m.am_signature) fmt
  and access = access2string m.am_access
  and exceptions fmt = pp_exceptions fmt m.am_exceptions
  and att fmt =
    pp_attributes fmt
      (fun _ -> fprintf fmt "@,@[<v>")
      (fun _ -> fprintf fmt "@]")
      (fun _ -> fprintf fmt "@,")
      m.am_attributes
  in
    fprintf fmt "@[<v 2>%t@[<3>%s@,abstract@ %t@ %t@]@,%t%t@]"
      anchor access sign exceptions (info.p_method cn m.am_signature) att

let pp_methods cn info fmt mm =
  pp_concat
    (function
      | AbstractMethod m -> pp_amethod cn info fmt m
      | ConcreteMethod m -> pp_cmethod cn info fmt m)
    (fun _ -> fprintf fmt "@,@[<v>")
    (fun _ -> fprintf fmt "@]")
    (fun _ -> fprintf fmt "@,@,")
    (MethodMap.fold (fun ms a l -> if info.f_method cn ms then a::l else l) mm [])


let pp_cfields cn info fmt fm =
  let pp_cfield fmt f =
    let access = access2string f.cf_access
    and anchor fmt = fs2anchor (cn,f.cf_signature) fmt
    and static = static2string f.cf_static
    and kind = kind2string f.cf_kind
    and value fmt = (match f.cf_value with
      | None -> ()
      | Some v -> fprintf fmt " =@ %s" (cstvalue2string v))
    and trans = (if f.cf_transient then "transient " else "")
    and attr fmt =
      pp_attributes fmt
	(fun _ -> fprintf fmt "@,@[<v>")
	(fun _ -> fprintf fmt "@]")
	(fun _ -> fprintf fmt "@,")
	f.cf_attributes
    and sign fmt = pp_field_signature fmt f.cf_signature
    in
      fprintf fmt
	"@[<hv 2>%t@[%s@,%s@,%s@,%s@,%t%t@]%t%t@]"
	anchor access static kind trans sign value (info.p_field cn f.cf_signature) attr
  in
    pp_concat
      (fun f -> pp_cfield fmt f)
      (fun _ ->fprintf fmt "@,@[<v>")
      (fun _ ->fprintf fmt "@]@,")
      (fun _ ->fprintf fmt "@,")
      (FieldMap.fold
	  (fun fs f l -> if info.f_field cn fs then f::l else l)
	  fm
	  [])

let pp_ifields cn info fmt fm =
  let pp_ifield fmt f =
    let value fmt = (match f.if_value with
      | None -> ()
      | Some v -> fprintf fmt " =@ %s" (cstvalue2string v))
    and anchor fmt = fs2anchor (cn,f.if_signature) fmt
    and attr fmt =
      pp_attributes fmt
	(fun _ -> fprintf fmt "@,@[<v>")
	(fun _ -> fprintf fmt "@]")
	(fun _ -> fprintf fmt "@,")
	f.if_attributes
    and sign fmt = pp_field_signature fmt f.if_signature
    in
      fprintf fmt
	"@[<hv 2>%t@[public@ static@ final@ %t%t@]%t%t@]"
	anchor sign value (info.p_field cn f.if_signature) attr
  in
    pp_concat
      (fun f -> pp_ifield fmt f)
      (fun _ ->fprintf fmt "@,@[<v>")
      (fun _ ->fprintf fmt "@]@,")
      (fun _ ->fprintf fmt "@,")
      (FieldMap.fold
	  (fun fs f l -> if info.f_field cn fs then f::l else l)
	  fm
	  [])
   

let pprint_class' info fmt (c:jclass) =
  if info.f_class c.c_name then
  (* the constant pool is not printed *)
  let cn = JDumpBasics.class_name c.c_name
  and anchor fmt = cn2anchor c.c_name fmt
  and access = access2string c.c_access
  and abstract = (if c.c_abstract then "abstract " else "")
  and final = final2string c.c_final
  and super fmt = match c.c_super_class with
    | None -> ()
    | Some super -> 
	fprintf fmt "extends %a "
	  (cn2link super) (JDumpBasics.class_name super)
  and interfaces fmt =
    match c.c_interfaces with
      | [] -> ()
      | il -> fprintf fmt "implements@ @[%a@]" pp_cinterfaces il
  and deprecated fmt = if c.c_deprecated then fprintf fmt "AttributeDeprecated@,"
  and source fmt = pp_source fmt c.c_sourcefile
  and inner_classes fmt = pp_inner_classes fmt c.c_inner_classes
  and other_attr fmt =
    pp_other_attr fmt ignore (fun _ -> fprintf fmt "@,")
      (fun _ -> fprintf fmt "@,") c.c_other_attributes
  and fields fmt = pp_cfields c.c_name info fmt c.c_fields
  and meths fmt = pp_methods c.c_name info fmt c.c_methods
  in
    fprintf fmt "@[<v>%t@[%s%s%sclass %s %t%t@]{@{<class>@;<0 2>@[<v>"
      anchor abstract access final cn super interfaces;
    fprintf fmt "@[<v>%t%t%t%t%t@]"
      (info.p_class c.c_name) source inner_classes deprecated other_attr;
    fprintf fmt "@[@ @ @[<v>%t%t@]@]" fields meths;
    fprintf fmt "@]@}@,}@,@]@?"

let pprint_interface' info fmt (c:jinterface) =
  if info.f_class c.i_name then
    let cn = JDumpBasics.class_name c.i_name in
    let anchor fmt = cn2anchor c.i_name fmt
    and access = access2string c.i_access
    and interfaces fmt =
      match c.i_interfaces with
	| [] -> ()
	| il -> fprintf fmt "extends@ @[%a@]" pp_cinterfaces il
    and deprecated fmt = if c.i_deprecated then fprintf fmt "AttributeDeprecated@,"
    and source fmt = pp_source fmt c.i_sourcefile
    and inner_classes fmt = pp_inner_classes fmt c.i_inner_classes
    and other_attr fmt =
      pp_other_attr fmt ignore (fun _ -> fprintf fmt "@,")
	(fun _ -> fprintf fmt "@,") c.i_other_attributes
    and fields fmt = pp_ifields c.i_name info fmt c.i_fields
    and clinit fmt = match c.i_initializer with
      | None -> ()
      | Some m ->
	  if info.f_method c.i_name m.cm_signature
	  then fprintf fmt "@[<v>%a@,@,@]" (pp_cmethod c.i_name info) m
    and meths fmt =
      pp_concat
	(pp_amethod c.i_name info fmt)
	(fun _ -> fprintf fmt "@[<v>")
	(fun _ -> fprintf fmt "@]")
	(fun _ -> fprintf fmt "@,@,")
	(MethodMap.fold (fun ms a l -> if info.f_method c.i_name ms then a::l else l) c.i_methods [])
    in
      fprintf fmt "@[<v>%t@[abstract@ %sinterface %s %t@]{@{<class>@;<0 2>@[<v>"
	anchor access cn interfaces;
      fprintf fmt "@[<v>%t%t%t%t%t@]"
	(info.p_class c.i_name) source inner_classes deprecated other_attr;
      fprintf fmt "@[@ @ @[<v>%t%t%t@]@]" fields clinit meths;
      fprintf fmt "@]@}@,}@,@]@?"

(** [to_text fmt] returns a formatter that is compatible with the
    latter function. {b side-effects:} The formatter is modified, so
    the behaviour with other pretty-printing function might not work
    anymore.*)
let to_text fmt =
  let html_mode = ref false in
  let (old_out,flush,newline,spaces) = pp_get_all_formatter_output_functions fmt () in
  let out str start arrival =
    if !html_mode
    then ()
    else old_out str start arrival
  in
    pp_set_all_formatter_output_functions fmt ~out ~flush ~newline ~spaces;
    pp_set_tags fmt true;
    pp_set_print_tags fmt false;
    pp_set_mark_tags fmt true;
    pp_set_formatter_tag_functions fmt
      {mark_open_tag = 
	  (function
	    | "html" -> html_mode := true;""
	    | _ -> "");
       mark_close_tag =
	  (function
	    | "html" -> html_mode := false;""
	    | _ -> "");
       print_open_tag = (fun _ -> ());
       print_close_tag = (fun _ -> ());
      };
    fmt


let to_html oc =
  let fmt = formatter_of_out_channel oc in
  let html_mode = ref false in
  let opening_tag = function
    | "html" -> html_mode := true; ""
    | s -> "<div class=\""^s^"\"><div onclick=\"hbrothers(this);\">-</div><div class=\"hideable\">"
  and closing_tag = function
    | "html" -> html_mode := false;""
    | s -> "</div></div><!-- "^s^" -->"
  in
  let (old_out,flush,_,_) = pp_get_all_formatter_output_functions fmt () in
  let finishes_by_space = ref false
  and new_line = ref true in
  let replace_spaces str =
    if str = "" then str
    else
      let str = 
	if (!finishes_by_space || !new_line) && str.[0] = ' '
	then "&nbsp;" ^(ExtString.String.slice ~first:1 str)
	else str
      in
	if str.[String.length str - 1] = ' '
	then finishes_by_space := true
	else finishes_by_space := false;
	snd (replace_all ~str ~sub:"  " ~by:" &nbsp;")
  in
  let out str start arrival =
    let str = String.sub str start arrival in
    let str =
      if !html_mode then
	str
      else
	begin
	  let (_,str) = replace_all ~str ~sub:"<" ~by:"&lt;" in
	  let (_,str) = replace_all ~str ~sub:">" ~by:"&gt;" in
	    replace_spaces str
	end
    in
      old_out str 0 (String.length str);
      new_line := false
  in
  let newline _ = 
    new_line := true;
    old_out "<br/>\n" 0 6 in
  let spaces80 = "                                                                                " in
  let rec spaces n =
    begin
      if n > 80 then
	let str = replace_spaces spaces80 in
	  (old_out str 0 80;spaces (n-80))
      else if n > 0 then
	let str = replace_spaces (String.sub spaces80 0 n) in
	  (old_out str 0 (String.length str))
    end;
    if n > 0 then new_line := false;
  in
    pp_set_all_formatter_output_functions fmt ~out ~flush ~newline ~spaces;
    pp_set_tags fmt true;
    pp_set_print_tags fmt false;
    pp_set_mark_tags fmt true;
    pp_set_formatter_tag_functions fmt
      {mark_open_tag = (fun s -> let str = opening_tag s in old_out str 0 (String.length str);"");
       mark_close_tag = (fun s -> let str = closing_tag s in old_out str 0 (String.length str);"");
       print_open_tag = (fun _ -> ());
       print_close_tag = (fun _ -> ());
      };
    fmt

let pprint_to_html_file pprint intro info file c =
  let ic = open_in_bin intro in
  let oc = open_out_bin file in
  let len = in_channel_length ic in
  let buff = String.create len in
  let fmt = to_html oc
  in
    really_input ic buff 0 len;
    close_in ic;
    output_string oc buff;
    pprint info fmt c;
    output_string oc "\n</body></html>\n";
    close_out oc

let pprint_class'' (info:info) fmt = function
  | `Class c -> pprint_class' info fmt c
  | `Interface c -> pprint_interface' info fmt c


let pprint_program'' info fmt prog =
  info.p_global fmt;
  pp_concat
    (fun c -> match (JProgram.to_class c) with
      | `Class c -> pprint_class' info fmt c
      | `Interface c -> pprint_interface' info fmt c)
    (fun _ -> fprintf fmt "@[<v>")
    (fun _ -> fprintf fmt "@]")
    (fun _ -> fprintf fmt "@,")
    (JProgram.fold
	(fun l c -> if info.f_class (JProgram.get_name c) then c::l else l)
	[] prog)

let pprint_class info fmt = pprint_class'' info (to_text fmt)
let pprint_program info fmt = pprint_program'' info (to_text fmt)

let pprint_class_to_html_file args = pprint_to_html_file pprint_class'' args
let pprint_program_to_html_file args = pprint_to_html_file pprint_program'' args

