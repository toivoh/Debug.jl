
#   Debug.Flow:
# =============
# Interactive debug trap

module Flow
using Base, Meta, AST, Eval
import AST.is_emittable
export @bp, BPNode, DBState


type BreakPoint <: Trap; end
typealias BPNode Leaf{BreakPoint}
is_emittable(::BPNode) = false

macro bp()
    Leaf(BreakPoint())
end


type DBState
    singlestep::Bool
    DBState() = new(false)
end

trap(s::DBState, ::BPNode,    scope::Scope) = (s.singlestep = true; false)
trap(s::DBState, ::BlockNode, scope::Scope) = false
trap(s::DBState, ::Node,      scope::Scope) = s.singlestep


end