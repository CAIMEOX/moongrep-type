///|
/// Wire layouts for moonc 7080b3792. This data describes the serialized protocol;
/// it is not generated from compiler sources and loads no compiler code.
/// Field tokens: * = list, ? = option, # = array; x = nonsemantic payload.
priv struct Shape {
  name : String
  type_slot : Int
  location_slot : Int
  fields : Array[String]
}

///|
fn shape(spec : String) -> Shape {
  let parts = spec.split("|").map(part => part.to_owned()).to_array()
  {
    name: parts[0],
    type_slot: schema_int(parts[1]),
    location_slot: schema_int(parts[2]),
    fields: parts[3].split(" ").map(part => part.to_owned()).to_array(),
  }
}

///|
let expressions : Array[Shape] = [
  "Texpr_apply|3|5|e *arg x t x l", "Texpr_method|5|6|v sub x tn x t l", "Texpr_unresolved_method|5|6|tn s t sub x t l",
  "Texpr_ident|4|5|v sub x x t l", "Texpr_as|2|4|e tn t x l", "Texpr_array|1|3|*e t x l",
  "Texpr_constant|1|3|x t ?v l", "Texpr_constr|3|5|?tn cn x t x l", "Texpr_labelled_block|2|3|lb e t l",
  "Texpr_while|3|5|e e ?e t ?lb l", "Texpr_function|1|-2|fn t x", "Texpr_if|3|4|e e ?e t l",
  "Texpr_letfn|3|5|b fn e t x l", "Texpr_letrec|2|3|*recbind e t l", "Texpr_let|4|5|p e *pb e t l",
  "Texpr_sequence|2|3|*e e t l", "Texpr_tuple|1|2|*e t l", "Texpr_record|2|4|?tn *fielddef t x l",
  "Texpr_record_update|4|6|?tn e #fieldinfo *fielddef t x l", "Texpr_field|3|5|e accessor x t x l",
  "Texpr_mutate|5|6|e label e x ?e t l", "Texpr_match|2|4|e *case t l l", "Texpr_desugared_lexscan|3|4|e *v *p t l",
  "Texpr_letmut|4|5|b ?ty e e t l", "Texpr_assign|3|4|v e ?e t l", "Texpr_hole|0|1|t l x",
  "Texpr_proof_assert|-2|1|e l", "Texpr_unit|-2|0|l", "Texpr_break|1|3|?e t ?lb l",
  "Texpr_continue|1|3|*e t ?lb l", "Texpr_loop|3|5|param e e t ?lb l", "Texpr_for|6|8|*bind ?e *step e ?e loopproof t ?lb l",
  "Texpr_foreach|7|9|foreachbind foreachkind *bind *step e ?e loopproof t ?lb l",
  "Texpr_return|1|2|?e t l", "Texpr_raise|1|2|e t l", "Texpr_try|4|9|e *case x ?*case t t x l l l",
  "Texpr_try_operator|3|4|e x x t l", "Texpr_constraint|2|3|e ty t l", "Texpr_pipe|2|3|e pipe t l",
  "Texpr_interp|1|2|*interp t l", "Texpr_guard|5|6|e ?e e x l t l", "Texpr_defer|2|4|e e t t l",
  "Texpr_errdefer|2|3|e e t l", "Texpr_postaction|2|3|e e t l", "Texpr_is|-3|3|e p *pb l",
  "Texpr_any_to_string|-4|1|e l", "Texpr_array_as_view|1|3|e t x l", "Texpr_string_as_view|-5|1|e l",
  "Texpr_bytes_as_view|-6|1|e l", "Texpr_and|-3|3|e e l l", "Texpr_or|-3|3|e e l l",
  "Texpr_not|-3|2|e l l", "Texpr_list_comprehension|3|4|comprehension ?e e t l",
].map(shape)

///|
let patterns : Array[Shape] = [
  "Tpat_alias|2|3|p b t l", "Tpat_any|0|1|t l", "Tpat_array|1|2|arraypat t l", "Tpat_bitstring|2|5|*bitpat bitrest t x x l",
  "Tpat_constant|1|3|x t ?v l", "Tpat_constr|4|8|?tn cn *constrarg x t x x *t l",
  "Tpat_or|2|3|p p t l", "Tpat_tuple|1|2|*p t l", "Tpat_var|1|2|b t l", "Tpat_record|2|4|*fieldpat x t x l",
  "Tpat_constraint|2|3|p ty t l", "Tpat_map|2|3|*mappat mapop t l", "Tpat_range|3|4|p p x t l",
  "Tpat_with|-7|2|p *bind l", "Tpat_constr_any|1|3|tn t *x l", "Tpat_constr_unknown|2|3|tn x t l",
].map(shape)

///|
let type_nodes : Array[Shape] = [
  "Tany|0|1|t l", "Tarrow|3|4|*ty ty errty t l", "T_tuple|1|2|*ty t l", "Tname|2|4|x *ty t x l",
  "Tobject|1|3|x t x l",
].map(shape)

///|
fn schema_int(s : String) -> Int {
  let mut n = 0
  for c in s {
    if c != '-' {
      n = n * 10 + c.to_int() - 48
    }
  }
  if s.has_prefix("-") {
    -n
  } else {
    n
  }
}
