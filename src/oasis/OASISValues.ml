
(** Parse, print and check values of OASIS file
    @author Sylvain Le Gall
  *)

open OASISTypes
open OASISGettext
open OASISUtils
open ExtString

(** The value exist but there is no easy way to represent it
  *)
exception Not_printable
(** It is not possible to combine values
  *)
exception Not_combinable


(** Always fail on update
  *)
let update_fail _ _ =
  raise Not_combinable

(** Hidden value to build phantom data storage
  *)
let blackbox =
  {
    parse  = 
      (fun s -> 
         failwithf1
           (f_ "Blackbox type cannot be set to the value '%s'")
           s);
    update = update_fail;
    print  = (fun _ -> raise Not_printable);
  }

module StdRegexp = 
struct 
  let r = Str.regexp

  let url       = r "http://[a-zA-Z0-9\\./_?&;=-]+"
  let copyright = r "\\((c)\\|(C)\\) * [0-9]+\\(-[0-9]+\\)?,? .*" 
  let modul     = r "[A-Z][A-Za-z0-9_]*"
end

(* Check that string match a Str.regexp *)
let regexp regexp error = 
  {
    parse = 
      (fun str -> 
         if Str.string_match regexp str 0 && 
            (Str.match_beginning ()) = 0 &&
            (Str.match_end ()) = (String.length str) then
           str
         else
           failwithf2
             (f_ "String '%s' is not a %s")
             str 
             (error ()));
    update = update_fail;
    print = (fun s -> s);
  }

(** Check that we have an URL *)
let url = 
  regexp
    StdRegexp.url
    (fun () -> s_ "URL")

(** Check that we a (C) copyright *)
let copyright =
  {
    parse = 
      (fun str ->
         if Str.string_match StdRegexp.copyright str 0 then
           str
         else
           failwithf1
             (f_ "Copyright must follow the convention \
                  '(C) 2008-2009 J.R. Hacker', here it is '%s'")
             str);
    update = update_fail;
    print = (fun s -> s);
  }


(** String *)
let string =
  { 
    parse =  (fun s -> s);
    update = (fun s1 s2 -> s1^" "^s2); 
    print =  (fun s -> s);
  }

(** String is not empty *)
let string_not_empty =
  {
    parse =
      (fun str ->
         if str <> "" then
           str
         else
           failwith (s_ "Expecting not empty string"));
    update = (fun s1 s2 ->s1^" "^s2);
    print = (fun s -> s);
  }

(** File *)
let file = 
  {string_not_empty with update = update_fail}

(** File with glob *)
let file_glob =
  {string_not_empty with update = update_fail}

(** Directory *)
let directory =
  {string_not_empty with update = update_fail}


(** Variable that should be first expanded (i.e. replace $(...) by values 
  *)
let expand value =
  (* TODO: check expandable value *)
  value

(** Convert a dot separated string into list, don't strip whitespace *)
let dot_separated value =
  {
    parse =
      (fun s ->
         List.map
           value.parse
           (String.nsplit
              s
              "."));
    update = 
      List.append;
    print =
      (fun lst ->
         String.concat "." 
           (List.map 
              value.print
              lst));
  }

(** Convert a comma separated string into list, strip whitespace *)
let comma_separated value =
  { 
    parse = 
      (fun s ->
         List.map 
           (fun s -> 
              value.parse 
                (String.strip s))
           (String.nsplit 
              s 
              ","));
    update = 
      List.append;
    print = 
      (fun lst ->
         String.concat ", "
           (List.map 
              value.print
              lst));
  }

(** Convert a blank separated string into list, strip empty component *)
let space_separated = 
  {
    parse = 
      (fun s ->
         List.filter 
           (fun s -> s <> "")
           (String.nsplit s " "));
    update = 
      List.append;
    print =
      (fun lst ->
         String.concat " " lst);
  }

(** Check that we have a version number *)
let version =
  {
    parse  = OASISVersion.version_of_string;
    update = update_fail;
    print  = OASISVersion.string_of_version;
  }

(** Check that we have a version constraint *)
let version_comparator = 
  {
    parse  = OASISVersion.comparator_of_string;
    update = update_fail;
    print  = OASISVersion.string_of_comparator;
  }

(** Split a string that with an optional value: "e1 (e2)" *)
let with_optional_parentheses main_value optional_value =
  let split_parentheses =
    Str.regexp "\\([^(]*\\)(\\([^)]*\\))"
  in
    {
      parse = 
        (fun str ->
           if Str.string_match split_parentheses str 0 then
             begin
               let s1, s2 = 
                 Str.matched_group 1 str,
                 Str.matched_group 2 str
               in
               let e1 = 
                 main_value.parse
                   (String.strip s1)
               in
               let e2 =
                 optional_value.parse
                   (String.strip s2)
               in
                 e1, Some e2
             end
           else 
             begin
               main_value.parse str, None
             end);
      update = update_fail;
      print =
        (function
           | v, None ->
               main_value.print v
           | v, Some opt ->
               Printf.sprintf "%s (%s)"
                 (main_value.print v)
                 (optional_value.print opt));
    }

(** Optional value *)
let opt value =
  {
    parse = (fun str -> Some (value.parse str));
    update = update_fail;
    print =
      (function
         | Some v -> value.print v
         | None -> raise Not_printable);
  }

(** Convert string to module list *)
let modules =
  comma_separated
    (regexp 
       StdRegexp.modul
       (fun () -> s_ "module"))

(** Convert string to file list *)
let files = 
  comma_separated file

(** Convert string to URL *)
let categories = 
  comma_separated url 

(** Choices 
  *)
let choices nm lst =
  {
    parse = 
      (fun str ->
         try 
           List.assoc 
             (String.lowercase str)
             (List.map 
               (fun (k, v) ->
                  String.lowercase k, v)
                  lst)
         with Not_found ->
           failwithf3
             (f_ "Unknown %s %S (possible: %s)")
             (nm ()) str
             (String.concat ", " (List.map fst lst)));
    update = update_fail;
    print =
      (fun v ->
         try
           List.assoc
             v
             (List.map
                (fun (s, v) -> v, s)
                lst)
         with Not_found ->
           failwithf1
             (f_ "Unexpected abstract choice value for %s")
             (nm ()));
  }

(** Convert string to boolean *)
let boolean =
  choices 
    (fun () -> s_ "boolean")
    ["true", true; "false", false]

(** Findlib package name 
  *)
let pkgname =
  {
    parse = 
      (fun s ->
         if String.contains s '.' then
           failwith (s_ "Findlib package name cannot contain '.'")
         else
           s);
    update = update_fail;
    print =
      (fun s -> s);
  }

(** Internal library
  *)
let internal_library =
  (* TODO: check that the library really exists *)
  {string with update = update_fail}

(** Command line 
  *)
let command_line = 
  { 
    parse = 
      (fun s ->
         match space_separated.parse s with 
           | cmd :: args ->
               cmd, args
           | [] ->
               failwithf1 (f_ "Commande line '%s' is invalid") s);
    update =
      (fun (cmd, args1) (arg2, args3) ->
         (cmd, args1 @ (arg2 :: args3)));
    print = 
      (fun (cmd, args) -> 
         space_separated.print (cmd :: args))
  }
