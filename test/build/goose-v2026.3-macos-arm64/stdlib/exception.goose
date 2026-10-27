// Exceptions built entirely on return ... from (docs/stdlib.md).
// Inspired by Lobster's modules/exception.lobster. See the reference for
// recursion and lifetime restrictions; this does not provide finally.
namespace exception;

// An empty array means success; a singleton owns the thrown value. This
// needs neither a default E nor a nullable reference into an exited frame.
fn handler<E, Body>() -> E[] {
    Body();
    return [];
}

// Catch runs after handler has returned, so another throw reaches the next
// enclosing handler. Iteration also works for variable-size error values.
fn try<E, Body, Catch>() {
    for error in handler<E>(Body) { Catch(error); }
}

// Discard an error, if any.
fn try<E, Body>() { handler<E>(Body); }

// Construct the error in handler's caller, before intermediate frames exit.
// As elsewhere in Goose, pass copy(value) for an existing non-fixed value.
// Every call path must have an enclosing handler with a compatible E.
fn throw(value) { return [value] from handler; }
