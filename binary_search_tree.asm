BITS 64

;; rbp, rbx, r12, r13, r14, r15 belong to calling function, called function must preserve their values

;; pass INTEGER: rdi, rsi, rdx, rcx, r8, r9, stack...
;; return INTEGER: rax, rdx

;; NOTE: If the return value is classified as MEMORY, a pointer to where the
;;       value should go is passed as a 'secret' first parameter in rdi
;;       (making all the other parameters move a position/register down)

extern arena_push, arena_pos, arena_pop, arena_pop_to, arena_clear
global bst_make, bst_clear, bst_insert, bst_find, bst_find_all, bst_inorder, bst_remove, bst_height, bst_size

%define BST_OPT_AVL 1

struc BST
    .size:    resq 1 ;; u64
    .height:  resq 1 ;; u64
    .arena:   resq 1 ;; Arena*
    .root:    resq 1 ;; Node*
    .key_cmp: resq 1 ;; Function Pointer
    .options: resb 1 ;; (BST.options & BST_OPT_AVL) ? AVL balancing : no balancing
endstruc

struc Entry
    .key: resq 1 ;; u64
    .val: resq 1 ;; void*
endstruc

struc Node
    .key:    resq 1 ;; u64
    .val:    resq 1 ;; void*
    .left:   resq 1 ;; Node*
    .right:  resq 1 ;; Node*
    .parent: resq 1 ;; Node*
    .bf:     resb 1 ;; s8
endstruc

;; This struct will be returned from functions via registers,
;; rax = .size, rdx = .entries
struc Entries
    .size: resq 1    ;; u64
    .entries: resq 1 ;; Entry** (note that a Entry*[] wouldn't do it, since FAMs are part of the structs memory layout)
                     ;;         (that would cause the struct to be classified MEMORY instead of our desired INTEGER)
endstruc

;; BST *bst_make(Arena *, Compare_Func key_cmp)
bst_make:
    ;; rdi -- Arena*
    ;; rsi -- Compare_Func
    mov r12, rdi
    mov r13, rsi

    mov rsi, BST_size
    call arena_push
    ;; rax -- BST*
    mov [rax+BST.arena], r12
    mov [rax+BST.key_cmp], r13
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
    ;; rsi -- key*
    ;; rdx -- value*
    push rbp
    mov rbp, rsp
    sub rsp, 40
    ;;  [rsp+32]         -- u64 depth of insertion point
    ;;  [rsp+24]         -- Node** (where to insert new node)
    mov [rsp+16], rdx ;; -- value*
    mov [rsp+8], rsi  ;; -- key*
    mov [rsp], rdi    ;; -- BST*

    call _find_insertion_point
    ;; rax -- Node**
    ;; rdx -- u64 depth of node in rax
    ;; rbx -- Node* parent
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
    ;; rax+Node.bf starts out as zero (as do .left and .right)
    mov [rax+Node.parent], rbx

    mov r8, [rsp+24] ;; Node**
    mov [r8], rax

    mov rdi, [rsp]
    inc qword [rdi+BST.size]
    mov rsi, [rdi+BST.height]
    test rsi, rsi
    jz .exit ;; height marked out of date
    mov rdx, [rsp+32]
    cmp rdx, rsi
    jl .exit
    inc qword [rdi+BST.height]
    ;; current height > insertion point height should never happen!

.exit:
    mov r8b, [rdi+BST.options]
    and r8b, BST_OPT_AVL
    jz .exit_end
    ;; retrace and, if necessary, rebalance tree
    ;; rdi -- BST*
    push rax
    mov rsi, rax
    call _avl_retrace_insertion
    ;; rax -- new Entry*
    pop rax
.exit_end:
    mov rsp, rbp
    pop rbp
    ret

;; Node *_find(BST *, void *key)
_find_insertion_point:
    ;; rdi -- BST*
    ;; rsi -- key*
    mov r14, rdi
    mov r15, rsi
    xor rbx, rbx

    ;; rax -- current Node**
    ;; r8 -- current key
    xor rdx, rdx ;; keep track of depth
    lea rax, [rdi+BST.root]
.find_loop:
    mov r9, [rax] ;; Node*
    test r9, r9
    jz .exit

    inc rdx
    mov rbx, r9
    mov r8, [r9+Node.key]

    mov rax, [r14+BST.key_cmp]
    mov rdi, r15
    mov rsi, r8
    call rax
    test rax, rax
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
    ;; rbx -- Node* parent
    ret

;; Entry *bst_find(BST *, void *key)
bst_find:
    ;; rdi -- BST*
    ;; rsi -- key*
    mov r12, [rdi+BST.root]
    mov r14, rdi
    mov r15, rsi
.find_loop:
    test r12, r12
    jz .exit_nil
    mov rax, [r14+BST.key_cmp]
    mov rdi, r15
    mov rsi, [r12+Node.key]
    call rax
    test rax, rax
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

;; Entries bst_find_all(BST *, Arena *, void *key)
bst_find_all:
    ;; rdi -- BST*
    ;; rsi -- Arena*
    ;; rdx -- key*
    push rbp
    mov rbp, rsp
    sub rsp, 40
    mov qword [rsp+32], 0   ;; -- Entries size
    ;;  [rsp+24]         -- save arena start pos (the position where Entries starts)
    mov [rsp+16], rdx ;; -- key*
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
    mov rax, [rsp]
    mov rax, [rax+BST.key_cmp]
    mov rdi, [rsp+16]
    mov rsi, [r12+Node.key]
    call rax
    test rax, rax
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

	test r12, r12
	jz .exit

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

;; Entry *bst_remove(BST *, Entry *entry)
bst_remove:
    ;; rdi -- BST*
    ;; rsi -- entry*
    lea r12, [rdi+BST.root]
    mov r14, rdi
    mov r15, rsi
    xor r9, r9
    xor rdx, rdx
.find_loop:
    mov r13, r9
    mov r9, [r12]
    test r9, r9
    jz .exit_nil
    mov rax, [r14+BST.key_cmp]
    mov rdi, [r15+Node.key]
    mov rsi, [r9+Node.key]
    call rax
    test rax, rax
    jl .less
    jg .greater
    ;; =
    ;; multimap: is it the correct reference? (if not, continue searching to the right)
    cmp r15, r9
    jne .greater
    dec qword [r14+BST.size]
    ;; mark height as 'outdated'
    mov qword [r14+BST.height], 0

    mov rdi, r9
    push r9
    call _shift_node
    ;; rdx contains direction
    mov [r12], rax
    xor rsi, rsi
    test rax, rax
    jz .p1
    push r13
    mov rsi, [rax+Node.parent] ;; start retracing from this node (action point)
    mov [rax+Node.parent], r13 ;; set new parent on replacement node
    mov r13b, [rdi+Node.bf]
    mov [rax+Node.bf], r13b    ;; replacement node gets bf of replaced (deleted) node
    pop r13
.p1:
    test rsi, rsi
    jnz .bf1
    mov rsi, r13
    test rsi, rsi
    jnz .bf1
    mov rsi, rdi
.bf1:
    cmp rsi, r9
    jne .not_current_node
    mov rsi, r13
.not_current_node:

    mov r8b, [r14+BST.options]
    and r8b, BST_OPT_AVL
    jz .exit_end
    ;; retrace and, if necessary, rebalance tree
    mov rdi, r14
    ;; rsi = action point (original parent of replacement candidate)
    ;; rdx = direction (coming from nowhere = 0, right = 1, or left = 2)
    call _avl_retrace_removal
.exit_end:
    pop rax
    ret
.less:
    lea r12, [r9+Node.left]
    mov rdx, 2
    jmp .find_loop
.greater:
    lea r12, [r9+Node.right]
    mov rdx, 1
    jmp .find_loop

.exit_nil:
    xor rax, rax
    ret

;; Node *<replacement_node> _shift_node(Node *current_node)
_shift_node:
    ;; rdi -- Node*
    push r12
    push r13
    push r14
    push r15
    mov r12, [rdi+Node.left]
    mov r13, [rdi+Node.right]
    test r12, r12
    jnz .left_non_zero
    test r13, r13
    jz .both_zero
    jmp .left_zero
.left_non_zero:
    test r13, r13
    jz .right_zero
    ;; both non-zero
    ;; r13 is replacement candidate
    ;; r14 is candidate parent
    xor r14, r14
.search_candidate:
    mov r12, [r13+Node.left]
    test r12, r12
    jz .candidate_found
    mov r14, r13
    mov r13, r12
    jmp .search_candidate
.candidate_found:
    mov r15, [rdi+Node.right]
    cmp r15, r13
    mov rdx, 1 ;; coming from right
    je .candidate_is_right_child
    mov rdx, 2 ;; coming from left
    ;; switch candidate with right child of current_node
    mov r8, [r13+Node.right]
    mov [r14+Node.left], r8
    test r8, r8
    jz .p1
    mov [r8+Node.parent], r14
.p1:
    mov [r13+Node.right], r15
    mov [r15+Node.parent], r13
.candidate_is_right_child:
    mov r15, [rdi+Node.left]
    mov [r13+Node.left], r15
    mov [r15+Node.parent], r13
    mov rax, r13 ;; return candidate
    pop r15
    pop r14
    pop r13
    pop r12
    ret

.left_zero:
    mov rax, r13 ;; return right child
    ;; leave value of rdx
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.right_zero:
    mov rax, r12 ;; return left child
    ;; leave value of rdx
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.both_zero:
    xor rax, rax ;; return NIL
    ;; leave value of rdx
    pop r15
    pop r14
    pop r13
    pop r12
    ret

struc Node_Height
    .node: resq 1   ;; Node*
    .height: resq 1 ;; u64 height
endstruc

;; u64 _bst_calc_height(BST *, Node* n)
global _bst_calc_height
_bst_calc_height:
    ;; rdi -- BST*
    ;; rsi -- Node*
    push rbp
    mov rbp, rsp
    sub rsp, 40
    mov r8, [rdi+BST.arena]
    mov qword [rsp+32], 0 ;; -- max height
    mov qword [rsp+24], 0 ;; -- number of elements on stack
    ;;  [rsp+16]    ;; -- top of stack
    mov [rsp+8], r8 ;; -- Arena*
    mov [rsp], rdi  ;; -- BST*

    test rsi, rsi ;; node passed in was null
    jz .exit

    xor r13, r13 ;; current path height
    mov r12, rsi ;; current node (start with n)
.calc_loop:
    mov rdi, [rsp+24]
    test rdi, rdi
    jz .check_next
    mov rdi, [rsp+16]
    mov rdi, [rdi]
    cmp rdi, r12
    jne .check_next

    mov rdi, [rsp+8]
    mov rsi, Node_Height_size
    call arena_pop
    dec qword [rsp+24]
    sub qword [rsp+16], Node_Height_size

    mov rdi, [r12+Node.right]
    test rdi, rdi
    jz .next_in_stack
    mov r12, rdi
    jmp .calc_loop

.next_in_stack:
    mov rdi, [rsp+24]
    test rdi, rdi
    jz .exit
    mov r8, [rsp+16]
    mov r12, [r8+Node_Height.node]
    mov r13, [r8+Node_Height.height]
    jmp .calc_loop

.check_next:
    inc r13
    mov rdi, [rsp+8]
    mov rsi, Node_Height_size
    call arena_push
    mov [rax+Node_Height.node], r12
    mov [rax+Node_Height.height], r13
    mov [rsp+16], rax
    inc qword [rsp+24]
    cmp r13, [rsp+32]
    jle .no_max
    mov [rsp+32], r13
.no_max:
    mov rdi, [r12+Node.left]
    test rdi, rdi
    jz .calc_loop
    mov r12, rdi
    jmp .calc_loop

.exit:
    mov rdi, [rsp]
    mov rax, [rsp+32] ;; rax -- max height
    mov rsp, rbp
    pop rbp
    ret

;; u64 bst_height(BST *)
bst_height:
    ;; rdi -- BST*
    mov rax, [rdi+BST.height]
    test rax, rax
    jnz .exit
    ;; rdi -- BST*
    mov rsi, [rdi+BST.root]
    call _bst_calc_height
    mov [rdi+BST.height], rax
.exit:
    ret

;; u64 bst_size(BST *)
bst_size:
    ;; rdi -- BST*
    mov rax, [rdi+BST.size]
    ret

;; void _avl_retrace_insertion(BST *, Node *)
_avl_retrace_insertion:
    ;; rdi -- BST*
    ;; rsi -- Node*
.retrace_loop:
    mov r15, [rsi+Node.parent]
    test r15, r15
    jz .exit
    mov r14, [r15+Node.left]
    cmp rsi, r14
    je .coming_from_left
.coming_from_right:
    inc byte [r15+Node.bf]
    mov rsi, r15
    call _avl_rebalance
    test rax, rax
    jz .retrace_loop
    jmp .exit
.coming_from_left:
    dec byte [r15+Node.bf]
    mov rsi, r15
    call _avl_rebalance
    test rax, rax
    jz .retrace_loop
.exit:
    ;; we can stop retracing after a single rotation or if a balance factor changed from ±1 to 0
    ret

;; void _avl_retrace_removal(BST *, Node *)
_avl_retrace_removal:
    ;; rdi -- BST*
    ;; rsi -- Node*
    ;; rdx -- coming from right = 1 or left = 2
    mov r15, rsi
    cmp rdx, 1
    je .coming_from_right
    cmp rdx, 2
    je .coming_from_left
    jmp .exit ;; shouldn't ever happen (@todo: make an assert)
.retrace_loop:
    test r15, r15
    jz .exit
    mov r14, [r15+Node.left]
    cmp rsi, r14
    je .coming_from_left
.coming_from_right:
    dec byte [r15+Node.bf]
    mov rsi, r15
    mov r15, [rsi+Node.parent]
    call _avl_rebalance
    test rax, rax
    jnz .retrace_loop
    jmp .exit
.coming_from_left:
    inc byte [r15+Node.bf]
    mov rsi, r15
    mov r15, [rsi+Node.parent]
    call _avl_rebalance
    test rax, rax
    jnz .retrace_loop
.exit:
    ;; we can stop retracing after a balance factor changed from 0 to ±1
    ;; n.b., rotating once (whether simple or double) might not be enough to bring the tree back into balance
    ret

;; bool<is re-balanced> _avl_rebalance(BST *, Node *)
_avl_rebalance:
    ;; rdi -- BST*
    ;; rsi -- Node*
    push r15
    mov r15b, [rsi+Node.bf]
    cmp r15b, 2
    je .z_is_right
    cmp r15b, -2
    je .z_is_left
    xor rax, rax
    cmp r15b, 0
    jne .exit
    mov rax, 5
    jmp .exit
.z_is_right:
    mov r14, [rsi+Node.right]
    mov r14b, [r14+Node.bf]
    test r14b, r14b
    jge .left_left  ;; X is unbalanced node, Z is right child and BF(Z) >= 0 --> rotate left
    jmp .right_left ;; X is unbalanced node, Z is right child and BF(Z) < 0 --> rotate right, rotate left
.z_is_left:
    mov r14, [rsi+Node.left]
    mov r14b, [r14+Node.bf]
    test r14b, r14b
    jle .right_right ;; Z is left child and BF(Z) <= 0 --> rotate left
    jmp .left_right  ;; Z is left child and BF(Z) > 0 --> rotate left, rotate right
.right_right:
    call _avl_rotate_right
    mov rax, 1
    pop r15
    ret
.right_left:
    call _avl_rotate_right_left
    mov rax, 2
    pop r15
    ret
.left_left:
    call _avl_rotate_left
    mov rax, 3
    pop r15
    ret
.left_right:
    call _avl_rotate_left_right
    mov rax, 4
.exit:
    pop r15
    ret

;; void _avl_rotate_left(BST *, Node *)
_avl_rotate_left:
    ;; rdi -- BST*
    ;; rsi -- Node*

    ;; P             P
    ;;  \             \
    ;;   X        =>   Z
    ;;  / \           / \
    ;; L*  Z         X  ZR*
    ;;    / \       / \
    ;;  ZL  ZR*    L*  ZL

    ;; P->right = X->right (Z)
    ;; root = X->right (Z) (if P is nil)
    mov r9, [rsi+Node.right]
    mov r8, [rsi+Node.parent]
    test r8, r8
    jnz .assign_parent
    mov [rdi+BST.root], r9
    mov qword [r9+Node.parent], 0
    jmp .rewire
.assign_parent:
    mov [r8+Node.right], r9
    mov [r9+Node.parent], r8
.rewire:
    ;; X->right = Z->left
    mov r10, [r9+Node.left]
    mov [rsi+Node.right], r10
    test r10, r10
    jz .p1
    mov [r10+Node.parent], rsi
.p1:

    ;; Z->left = X
    mov [r9+Node.left], rsi
    mov [rsi+Node.parent], r9

    mov r10b, [r9+Node.bf]
    test r10b, r10b
    jnz .bf_non_zero
    mov byte [rsi+Node.bf], 1
    mov byte [r9+Node.bf], -1
.bf_non_zero:
    mov byte [rsi+Node.bf], 0
    mov byte [r9+Node.bf], 0
    ret

;; void _avl_rotate_right(BST *, Node *)
_avl_rotate_right:
    ;; rdi -- BST*
    ;; rsi -- Node*

    ;;       P               P
    ;;      /               /
    ;;     X               Z
    ;;    / \     =>      / \
    ;;   Z   R*          ZL* X
    ;;  / \                 / \
    ;; ZL* ZR              ZR  R*

    ;; P->left = X->left
    ;; root = X->left (if P is nil)
    mov r9, [rsi+Node.left]
    mov r8, [rsi+Node.parent]
    test r8, r8
    jnz .assign_parent
    mov [rdi+BST.root], r9
    mov qword [r9+Node.parent], 0
    jmp .rewire
.assign_parent:
    mov [r8+Node.left], r9
    mov [r9+Node.parent], r8
.rewire:
    ;; X->left = Z->right
    mov r10, [r9+Node.right]
    mov [rsi+Node.left], r10
    test r10, r10
    jz .p1
    mov [r10+Node.parent], rsi
.p1:

    ;; Z->right = X
    mov [r9+Node.right], rsi
    mov [rsi+Node.parent], r9

    mov r10b, [r9+Node.bf]
    test r10b, r10b
    jnz .bf_non_zero
    mov byte [rsi+Node.bf], 1
    mov byte [r9+Node.bf], -1
.bf_non_zero:
    mov byte [rsi+Node.bf], 0
    mov byte [r9+Node.bf], 0
    ret

_avl_rotate_right_left:
    ;; rdi -- BST*
    ;; rsi -- Node*

    ;; X         X
    ;;  \         \
    ;;   Z         ZL
    ;;  / \    =>   \
    ;; ZL  ZR        Z
    ;;  \           / \
    ;;   R         R   ZR

    mov r8, rsi               ;; r8 = X (Z->parent)
    mov rsi, [rsi+Node.right] ;; rsi = Z
    mov r9, [rsi+Node.left]   ;; r9 = ZL
    mov [r8+Node.right], r9   ;; X->right = ZL
    mov [r9+Node.parent], r8
    mov r10, [r9+Node.right]
    mov [rsi+Node.left], r10  ;; Z->left = R
    test r10, r10
    jz .p1
    mov [r10+Node.parent], rsi
.p1:
    mov [r9+Node.right], rsi  ;; ZL->right = Z
    mov [rsi+Node.parent], r9

    ;; X              ZL
    ;;  \            /  \
    ;;   ZL         X    Z
    ;;  / \     =>   \  / \
    ;; L   Z         L  R  ZR
    ;;    / \
    ;;   R   ZR

    mov rsi, r8               ;; rsi = X
    mov r9, [rsi+Node.right]  ;; r9 = ZL
    mov r8, [rsi+Node.parent] ;; r8 = X->parent (may be nil)
    test r8, r8
    jnz .assign_parent
    mov [rdi+BST.root], r9    ;; root = ZL
    mov qword [r9+Node.parent], 0
    jmp .rotate
.assign_parent:
    mov [r8+Node.right], r9   ;; P->right = ZL
    mov [r9+Node.parent], r8
.rotate:
    mov r10, [r9+Node.left]
    mov [rsi+Node.right], r10 ;; X->right = L
    test r10, r10
    jz .p2
    mov [r10+Node.parent], rsi
.p2:
    mov [r9+Node.left], rsi   ;; ZL->left = X
    mov [rsi+Node.parent], r9

    mov r8, [r9+Node.right] ;; rsi = X, r9 = ZL,  r8 = Z
    mov r15b, [r9+Node.bf]
    mov byte [r9+Node.bf], 0
    test r15b, r15b
    jg .bf_greater
    jl .bf_lesser
.bf_zero:
    mov byte [rsi+Node.bf], 0
    mov byte [r8+Node.bf], 0
    ret
.bf_greater:
    mov byte [rsi+Node.bf], -1
    mov byte [r8+Node.bf], 0
    ret
.bf_lesser:
    mov byte [rsi+Node.bf], 0
    mov byte [r8+Node.bf], 1
    ret

_avl_rotate_left_right:
    ;; rdi -- BST*
    ;; rsi -- Node*

    ;;     X            X
    ;;    /            /
    ;;   Y    =>      Z
    ;;  / \          /
    ;; YL  Z        Y
    ;;    /        / \
    ;;   ZL      YL   ZL

    mov r8, rsi               ;; r8 = X (Y->parent)
    mov rsi, [rsi+Node.left]  ;; rsi = Y
    mov r9, [rsi+Node.right]  ;; r9 = Z
    mov [r8+Node.left], r9    ;; X->left = Z
    mov [r9+Node.parent], r8
    mov r10, [r9+Node.left]
    mov [rsi+Node.right], r10 ;; Y->right = ZL
    test r10, r10
    jz .p1
    mov [r10+Node.parent], rsi
.p1:
    mov [r9+Node.left], rsi   ;; Z->left = Y
    mov [rsi+Node.parent], r9

    ;;        X        Z
    ;;       /        / \
    ;;      Z        Y   X
    ;;     /    =>  /   / \
    ;;    Y        YL  ZL  XR
    ;;   / \
    ;; YL   ZL

    mov rsi, r8               ;; rsi = X
    mov r9, [rsi+Node.left]   ;; r9 = Z
    mov r8, [rsi+Node.parent] ;; r8 = X->parent (may be nil)
    test r8, r8
    jnz .assign_parent
    mov [rdi+BST.root], r9    ;; root = Z
    mov qword [r9+Node.parent], 0
    jmp .rotate
.assign_parent:
    mov [r8+Node.left], r9    ;; P->left = Z
    mov [r9+Node.parent], r8
.rotate:
    mov r10, [r9+Node.right]
    mov [rsi+Node.left], r10  ;; X->left = Z->right
    test r10, r10
    jz .p2
    mov [r10+Node.parent], rsi
.p2:
    mov [r9+Node.right], rsi  ;; Z->right = X
    mov [rsi+Node.parent], r9

    mov r8, [r9+Node.left] ;; r8 = Y, r9 = Z, rsi = X
    mov r15b, [r9+Node.bf]
    mov byte [r9+Node.bf], 0
    test r15b, r15b
    jg .bf_greater
    jl .bf_lesser
.bf_zero:
    mov byte [rsi+Node.bf], 0
    mov byte [r8+Node.bf], 0
    ret
.bf_greater:
    mov byte [rsi+Node.bf], 0
    mov byte [r8+Node.bf], -1
    ret
.bf_lesser:
    mov byte [rsi+Node.bf], 1
    mov byte [r8+Node.bf], 0
    ret

;; @todo: test rebalance, rotate implementations are correct (especially the double rotations)
;; @todo: bulk and set operations (see Wikipedia:AVL_tree)

section .bss

section .data
