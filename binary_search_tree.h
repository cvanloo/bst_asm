#pragma once

#include "arena.h"

typedef struct Node Node;
struct Node {
    U64 key;
    void* val;
    Node* left;
    Node* right;
};

typedef struct Entry Entry;
struct Entry {
    U64 key;
    void* val;
};

typedef struct BST BST;
struct BST {
    U64 size;
    U64 height;
    Arena *arena;
    Node *root;
};

extern BST *bst_make(Arena *);
extern void bst_clear(BST *);
extern Entry *bst_insert(BST *, U64 key, void *value);
extern Entry *bst_find(BST *, U64 key);
