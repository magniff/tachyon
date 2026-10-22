# c-mixed-build: a vole program and a C file, linked into one executable.
#
#   make                 # builds ./c-mixed-build
#   make run             # and runs it on a few readings
#   make VOLEC=volec   # a volec on the PATH instead of the tree's

VOLEC ?= ../../target/volec
CC ?= cc

c-mixed-build: main.o ring.o
	$(CC) main.o ring.o -o $@

# The C view of the vole program: on_evict and EVICTIONS, for ring.c.
main.h: main.vl
	$(VOLEC) --emit-header main.vl -o $@

ring.o: ring.c ring.h main.h
	$(CC) -O2 -c ring.c -o $@

# main.vl imports ring.h: it is rebuilt when the header changes.
main.o: main.vl ring.h
	$(VOLEC) main.vl -o $@

run: c-mixed-build
	echo 10 20 30 40 55 15 60 5 25 | ./c-mixed-build

clean:
	rm -f c-mixed-build main.o ring.o main.h

.PHONY: run clean
