(*
 *  This file is part of JavaLib
 *  Copyright (c)2007-2008 Université de Rennes 1 / CNRS
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

(** Builds high level representations of java byte-code programs using basic
    Class Reachability Analysis. *)

(** [parse_program classpath names] parses a list of [.jar] and
    [.class] files, looking for them in the classpath (a list of
    directories and [.jar] files separated with ':') . *)
val parse_program : string -> string list -> JProgram.program
val add_file :
  JFile.class_path -> JClass.interface_or_class -> JProgram.program -> JProgram.program