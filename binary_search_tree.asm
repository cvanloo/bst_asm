BITS 64

;; rbp, rbx, r12, r13, r14, r15 belong to calling function, called function must preserve their values

;; pass INTEGER: rdi, rsi, rdx, rcx, r8, r9, stack...
;; return INTEGER: rax, rdx

extern arena_push, arena_pop, arena_pop_to, arena_clear
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

;; BST *bst_make(Arena *)
bst_make:
    ;; rdi -- Arena*
    mov rsi, BST_size
    call arena_push
    ;; rax -- BST*
    mov [rax+BST.arena], rdi
    ret

;; void bst_clear(BST *)
bst_clear:
    mov qword [rdi+BST.size], 0

;; Entry *bst_insert(BST *, Entry)
bst_insert:
    ;; rdi -- BST*
    ;; rsi -- key
    ;; rdx -- value*
    push rbp
    mov rbp, rsp
    sub rsp, 32
    ;;  [rsp+24]         -- Node** (where to insert new node)
    mov [rsp+16], rdx ;; -- value*
    mov [rsp+8], rsi  ;; -- key
    mov [rsp], rdi    ;; -- BST*

    call _find
    ;; rax -- Node**
    mov [rsp+24], rax

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

.exit:
    ;; rax -- new Entry*
    mov rsp, rbp
    pop rbp
    ret

;; Node *_find(BST *, u64 key)
_find:
    ;; rdi -- BST*
    ;; rsi -- key

    ;; rax -- current Node**
    ;; r8 -- current key
    lea rax, [rdi+BST.root]
.find_loop:
    mov r9, [rax] ;; Node*
    test r9, r9
    jz .exit

    mov r8, [rax+Node.key]
    cmp r8, rsi
    jl .less
    ;; >=
    lea rax, [rax+Node.right]
    jmp .find_loop

.less:
    lea rax, [rax+Node.left]
    jmp .find_loop

.exit:
    ;; rax -- Node** (rax -> x -> NIL)
    ret

bst_find:
bst_find_all:
bst_inorder:
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
