(*
 *  This file is part of JavaLib
 *  Copyright (c)2007 Université de Rennes 1
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

(** Basic elements of class files. *)

(** {2 Types and descriptors.} *)

(** Fully qualified ordinary class or interface name (not an array).
    For example: [\["java" ; "lang" ; "Object"\]]. *)
type class_name = string list

(** Numerical types that are not smaller than int. *)
type other_num = [
| `Long
| `Float
| `Double
]

(** JVM basic type (int = short = char = byte = bool). *)
type jvm_basic_type = [
| `Int2Bool
| other_num
]

(** JVM type (int = short = char = byte = bool, all objects have the same type). *)
type jvm_type = [
| jvm_basic_type
| `Object
]

(** JVM array element type (byte = bool, all objects have the same type). *)
type jvm_array_type = [
| `Int
| `Short
| `Char
| `ByteBool
| other_num
| `Object
]

(** JVM return type (byte = bool, all objects have the same type). *)
type jvm_return_type = [
|  jvm_basic_type
| `Object
| `Void
]

(** Java basic type. *)
type java_basic_type = [
| `Int
| `Short
| `Char
| `Byte
| `Bool
| other_num
]

(** Java object type *)
type object_type =
  | TClass of class_name
  | TArray of value_type

(** Java type *)
and value_type =
  | TBasic of java_basic_type
  | TObject of object_type

(** Field descriptor. *)
type field_descriptor = value_type

(** Method descriptor. *)
type method_descriptor = value_type list * value_type option

(** Signatures parsed from CONSTANT_NameAndType_info structures. *)
type signature =
  | SValue of field_descriptor
  | SMethod of method_descriptor

(** Stackmap type. *)
type verification_type = 
	| VTop 
	| VInteger 
	| VFloat
	| VDouble
	| VLong
	| VNull
	| VUninitializedThis
	| VObject of object_type
	| VUninitialized of int (** creation point *)

(** {2 Exception handlers.} *)

(** Exception handler. *)
type jexception = {
	e_start : int;
	e_end : int;
	e_handler : int;
	e_catch_type : class_name option
}

(** {2 Constants.} *)

(** You should not need this for normal usage, as the
    parsing/unparsing functions take care of the constant pool. *)

(** Constant value. *)
type constant_value =
  | ConstString of string
  | ConstInt of int32
  | ConstFloat of float
  | ConstLong of int64
  | ConstDouble of float
  | ConstClass of object_type (** This is not documented in the JVM spec. *)

(** Constant. *)
type constant =
  | ConstValue of constant_value
  | ConstField of (class_name * string * field_descriptor)
  | ConstMethod of (object_type * string * method_descriptor)
  | ConstInterfaceMethod of (class_name * string * method_descriptor)
  | ConstNameAndType of string * signature
  | ConstStringUTF8 of string
  | ConstUnusable

(** For unparsing purposes: *)

(** Return the index of a constant, adding it to the constant pool if necessary.
    This is usefull for adding a user-defined attribute that refers to the constant pool. *)
val constant_to_int : constant DynArray.t -> constant -> int

(**/**)

type error_msg =
    Invalid_data
  | Invalid_constant of int
  | Invalid_access_flags of int
  | Custom of string

exception Error of string

val error : string -> 'a

val get_constant : constant array -> int -> constant

val get_constant_value : constant array -> int -> constant_value

val get_object_type : constant array -> int -> object_type
val get_class : constant array -> int -> class_name

val get_string : constant array -> IO.input -> string
val get_string' : constant array -> int -> string

val get_field : constant array -> int ->
  class_name * string * field_descriptor

val get_method : constant array -> int ->
  object_type * string * method_descriptor

val get_interface_method : constant array -> int ->
  class_name * string * method_descriptor

(* This should go somewhere else. *)

val write_ui8 : 'a IO.output -> int -> unit
val write_i8 : 'a IO.output -> int -> unit
val write_constant :
  'a IO.output -> constant DynArray.t -> constant -> unit
val write_string_with_length :
  ('a IO.output -> int -> 'b) -> 'a IO.output -> string -> unit
val write_with_length :
  ('a IO.output -> int -> 'b) ->
  'a IO.output -> (string IO.output -> 'c) -> unit
val write_with_size :
  ('a -> int -> 'b) -> 'a -> ('c -> unit) -> 'c list -> unit