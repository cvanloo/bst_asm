BITS 64

;; rbp, rbx, r12, r13, r14, r15 belong to calling function, called function must preserve their values

;; pass INTEGER: rdi, rsi, rdx, rcx, r8, r9, stack...
;; return INTEGER: rax, rdx

;; NOTE: If the return value is classified as MEMORY, a pointer to where the
;;       value should go is passed as a 'secret' first parameter in rdi
;;       (making all the other parameters move a position/register down)

extern arena_push, arena_pos, arena_pop, arena_pop_to, arena_clear
global bst_make, bst_clear, bst_insert, bst_find, bst_find_all, bst_inorder, bst_remove, bst_height, bst_size

struc BST
    .size:   resq 1 ;; u64
    .height: resq 1 ;; u64
    .arena:  resq 1 ;; Arena*
    .root:   resq 1 ;; Node*
endstruc

struc Entry
    .key: resq 1 ;; u64
    .val: resq 1 ;; void*
endstruc

struc Node
    .key:   resq 1 ;; u64
    .val:   resq 1 ;; void*
    .left:  resq 1 ;; Node*
    .right: resq 1 ;; Node*
endstruc

;; This struct will be returned from functions via registers,
;; rax = .size, rdx = .entries
struc Entries
    .size: resq 1    ;; u64
    .entries: resq 1 ;; Entry** (note that a Entry*[] wouldn't do it, since FAMs are part of the structs memory layout)
                     ;;         (that would cause the struct to be classified MEMORY instead of our desired INTEGER)
endstruc

;; BST *bst_make(Arena *)
bst_make:
    ;; rdi -- Arena*
    mov r12, rdi

    mov rsi, BST_size
    call arena_push
    ;; rax -- BST*
    mov [rax+BST.arena], r12
    ret

;; void bst_clear(BST *)
bst_clear:
    mov qword [rdi+BST.size], 0
    mov qword [rdi+BST.height], 0
    mov qword [rdi+BST.root], 0
    ret

;; Entry *bst_insert(BST *, Entry)
bst_insert:
    ;; rdi -- BST*
    ;; rsi -- key
    ;; rdx -- value*
    push rbp
    mov rbp, rsp
    sub rsp, 40
    ;;  [rsp+32]         -- u64 depth of insertion point
    ;;  [rsp+24]         -- Node** (where to insert new node)
    mov [rsp+16], rdx ;; -- value*
    mov [rsp+8], rsi  ;; -- key
    mov [rsp], rdi    ;; -- BST*

    call _find_insertion_point
    ;; rax -- Node**
    ;; rdx -- u64 depth of node in rax
    mov [rsp+24], rax
    mov [rsp+32], rdx

    mov rdi, [rsp]
    mov rdi, [rdi+BST.arena]
    mov rsi, Node_size
    call arena_push
    ;; rax -- Node*
    mov r12, [rsp+8]
    mov [rax+Node.key], r12
    mov r12, [rsp+16]
    mov [rax+Node.val], r12

    mov r8, [rsp+24] ;; Node**
    mov [r8], rax

    mov rdi, [rsp]
    inc qword [rdi+BST.size]
    mov rsi, [rdi+BST.height]
    mov rdx, [rsp+32]
    cmp rdx, rsi
    jl .exit
    inc qword [rdi+BST.height]
    ;; current height > insertion point height should never happen!

.exit:
    ;; rax -- new Entry*
    mov rsp, rbp
    pop rbp
    ret

;; Node *_find(BST *, u64 key)
_find_insertion_point:
    ;; rdi -- BST*
    ;; rsi -- key

    ;; rax -- current Node**
    ;; r8 -- current key
    xor rdx, rdx ;; keep track of depth
    lea rax, [rdi+BST.root]
.find_loop:
    mov r9, [rax] ;; Node*
    test r9, r9
    jz .exit

    inc rdx
    mov r8, [r9+Node.key]
    cmp rsi, r8
    jl .less
    ;; >=
    lea rax, [r9+Node.right]
    jmp .find_loop

.less:
    lea rax, [r9+Node.left]
    jmp .find_loop

.exit:
    ;; rax -- Node** (rax -> x -> NIL)
    ;; rdx -- u64 depth of insertion point
    ret

;; Entry *bst_find(BST *, u64 key)
bst_find:
    ;; rdi -- BST*
    ;; rsi -- key
    mov r12, [rdi+BST.root]
.find_loop:
    test r12, r12
    jz .exit_nil
    mov r13, [r12+Node.key]
    cmp rsi, r13
    jl .less
    jg .greater
    ;; =
    mov rax, r12 ;; found Entry*
    ret
.less:
    mov r12, [r12+Node.left]
    jmp .find_loop
.greater:
    mov r12, [r12+Node.right]
    jmp .find_loop
.exit_nil:
    xor rax, rax ;; not found, NIL
    ret

;; Entries bst_find_all(BST *, Arena *, u64 key)
bst_find_all:
    ;; rdi -- BST*
    ;; rsi -- Arena*
    ;; rdx -- key
    push rbp
    mov rbp, rsp
    sub rsp, 40
    mov qword [rsp+32], 0   ;; -- Entries size
    ;;  [rsp+24]         -- save arena start pos (the position where Entries starts)
    mov [rsp+16], rdx ;; -- key
    mov [rsp+8], rsi  ;; -- Arena*
    mov [rsp], rdi    ;; -- BST*

    ;; @fixme: probably not a good idea to access arena internals like this
    ;;         maybe we should add a method to the arena's interface for this?
    mov rdi, [rsp+8]
    mov r12, [rdi+8]   ;; arena->pos
    lea rax, [rdi+32]  ;; arena->data
    lea rax, [rax+r12] ;; arena->data[arena->pos]
    mov [rsp+24], rax

    mov rdi, [rsp]
    mov r12, [rdi+BST.root]
.find_loop:
    test r12, r12
    jz .exit
    mov r13, [r12+Node.key]
    cmp [rsp+16], r13
    jl .less
    jg .greater
    ;; =
    mov rdi, [rsp+8]
    mov rsi, 8 ;; pointer size (Entry *)
    call arena_push
    mov [rax], r12
    inc qword [rsp+32]
    ;; multimap: continue with greater, 'cause multiple of the same key might be stored there
.greater:
    mov r12, [r12+Node.right]
    jmp .find_loop
.less:
    mov r12, [r12+Node.left]
    jmp .find_loop

.exit:
    ;; rax -- size
    ;; rdx -- Entry** (as in array of pointers to entries)
    mov rax, [rsp+32]
    mov rdx, [rsp+24]
    mov rsp, rbp
    pop rbp
    ret

;; void bst_inorder(BST *, Entry_Callback cb)
bst_inorder:
    ;; rdi -- BST*
    ;; rsi -- callback
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp+24], 0 ;; -- number of elements on stack
    ;;  [rsp+16]        -- top of stack
    mov [rsp+8], rsi ;; -- callback
    mov [rsp], rdi   ;; -- BST*

    ;; we are using the arena as an actual stack here, to 'simulate' the recursive in-order traversal in an iterative way

    mov rdi, [rsp]
    mov r12, [rdi+BST.root] ;; r12 keeps track of  current node

.inorder_loop:
    mov rdi, [rsp+24]
    test rdi, rdi
    jz .check_next
    mov rdi, [rsp+16]
    mov rdi, [rdi]
    cmp rdi, r12 ;; current == stack.peek()
    jne .check_next

    ;; callback(current_entry)
    mov rdi, r12
    call [rsp+8]

    ;; stack.pop()
    mov rdi, [rsp]
    mov rdi, [rdi+BST.arena]
    mov rsi, 8
    call arena_pop
    dec qword [rsp+24]
    sub qword [rsp+16], 8

    mov rdi, [r12+Node.right]
    test rdi, rdi
    jz .next_in_stack
    mov r12, rdi
    jmp .inorder_loop

.next_in_stack:
    mov rdi, [rsp+24]
    test rdi, rdi
    jz .exit
    mov r12, [rsp+16]
    mov r12, [r12]
    jmp .inorder_loop

.check_next:
    ;; stack.push(current)
    mov rdi, [rsp]
    mov rdi, [rdi+BST.arena]
    mov rsi, 8
    call arena_push
    mov [rax], r12
    mov [rsp+16], rax
    inc qword [rsp+24]

    mov rdi, [r12+Node.left]
    test rdi, rdi
    jz .inorder_loop
    mov r12, rdi
    jmp .inorder_loop

.exit:
    xor rax, rax ;; don't return anything, clean up register anyways
    xor rdx, rdx
    mov rsp, rbp
    pop rbp
    ret

bst_remove:

;; u64 bst_height(BST *)
bst_height:
    ;; rdi -- BST*
    mov rax, [rdi+BST.height]
    ret

;; u64 bst_size(BST *)
bst_size:
    ;; rdi -- BST*
    mov rax, [rdi+BST.size]
    ret

section .bss

section .data
