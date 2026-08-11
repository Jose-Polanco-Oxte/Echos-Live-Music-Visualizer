---
name: rust-ownership
description: >-
  Rust ownership, borrowing, lifetimes, and smart pointers — the mental model plus concrete fixes for borrow-checker errors. Use when fighting the borrow checker, deciding between T / &T / &mut T, choosing Box/Rc/RefCell/Cow, returning references, writing an RAII/scope guard, or lazily initializing a value. Triggers: borrow checker, cannot borrow, does not live long enough, Rc, RefCell, Cow, RAII, OnceLock, E0382, E0499, E0515, E0597, E0716.
---

# Rust Ownership

The model, then the fixes. Ownership is one set of rules enforced at compile time — once the
model is in your head, the errors become mechanical. Deep dives are in the sub-files.

## When to Use

- The borrow checker is rejecting code (move / borrow / lifetime error)
- Designing a function signature: take `T`, `&T`, or `&mut T`?
- Choosing a container for sharing/mutation: `Box`, `Rc`, `RefCell`, `Cow`
- Returning a reference and hitting lifetime errors
- Tying cleanup to a scope (RAII/scope guard) or lazily initializing a value (`OnceLock`/`LazyLock`)

## The model in four rules

1. **Every value has exactly one owner.** When the owner goes out of scope, the value is dropped.
2. **Assignment/passing moves** non-`Copy` values: the source is invalidated. `Copy` types
   (integers, `bool`, `char`, shared refs, tuples/arrays of `Copy`) are duplicated instead.
3. **Borrowing**: `&T` is a shared (read) reference, `&mut T` is an exclusive (write) reference.
4. **The borrow rule**: at any time you may have **either** any number of `&T` **or** exactly
   one `&mut T` — never both. And a reference must never outlive the value it points to.

Everything the borrow checker says is one of these being violated. The fix is almost never
"add `.clone()`" — it's to satisfy the rule a different way.

## Error → fix

| Error | Meaning | First thing to try | Where |
|---|---|---|---|
| **E0382** | use of moved value | borrow (`&x`) instead of moving; or restructure so the move is last | [borrowing.md](borrowing.md) |
| **E0499** | two `&mut` to the same value | shorten one borrow's scope (NLL); split into disjoint fields | [borrowing.md](borrowing.md) |
| **E0502** | `&` and `&mut` at once | finish reading before mutating; copy the read value out first | [borrowing.md](borrowing.md) |
| **E0505** | move while borrowed | end the borrow before the move; clone if genuinely needed | [borrowing.md](borrowing.md) |
| **E0597** | borrowed value doesn't live long enough | extend the owner's scope; store the owner, not the borrow | [lifetimes.md](lifetimes.md) |
| **E0515** | returns a reference to a local | return the owned value, or `Cow` | [lifetimes.md](lifetimes.md) |
| **E0106** | missing lifetime specifier | annotate the relationship between input and output refs | [lifetimes.md](lifetimes.md) |
| **E0507** | cannot move out of borrowed content | `clone`, `std::mem::take`/`replace`, or `match` by reference | [borrowing.md](borrowing.md) |

## Decision: own or borrow in a signature?

Default to borrowing inputs; own only when you must store or consume.

| Take | When |
|---|---|
| `&T` | you only read it |
| `&mut T` | you mutate it in place and the caller keeps it |
| `T` | you store it, consume it, or need ownership (e.g. move into a thread/struct) |
| `impl AsRef<str>` / `&str` | flexible read-only string input (accepts `String` and `&str`) |
| `impl Into<String>` | you'll own a `String` but want callers to pass either |

Returning: prefer returning owned `T`. Return `&T` only when it clearly borrows from an input
(and let elision write the lifetime). For "borrowed usually, owned sometimes" → `Cow`
([lifetimes.md](lifetimes.md)).

## Decision: which pointer?

Quick guide; full treatment in [pointers.md](pointers.md).

| Need | Use |
|---|---|
| Heap allocation / recursive type / trait object | `Box<T>` |
| Multiple owners, single thread | `Rc<T>` |
| Mutate through a shared/`&` reference, single thread | `RefCell<T>` (or `Cell<T>` for `Copy`) |
| Shared *and* mutable, single thread | `Rc<RefCell<T>>` |
| Break a reference cycle | `Weak<T>` |
| Any sharing **across threads** | `Arc` / `Mutex` → see `rust-concurrency` |

## Resource lifecycle: guards and lazy init

Once you own a resource, two questions follow: *when does its cleanup run* and *when is it
created*. RAII/scope guards tie cleanup to a scope (it can't be skipped by `?`, early return, or
panic); `OnceLock`/`LazyLock` defer creation to first use. Full treatment — including the
`let _ =` footgun and the transaction-rollback "defuse" pattern — in [lifecycle.md](lifecycle.md).

## Boundary

- Anything crossing threads — `Arc<Mutex<T>>`, `Send`/`Sync`, channels — is `rust-concurrency`.
  This skill is the single-threaded ownership model.
- Lifetimes *in trait bounds and generic design* → `rust-traits`; the mechanics of
  lifetimes live here.
