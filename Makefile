a.out: main.c binary_search_tree.h binary_search_tree.o
	clang main.c binary_search_tree.h binary_search_tree.o -ggdb

binary_search_tree.o: binary_search_tree.asm
	nasm -felf64 binary_search_tree.asm -g
