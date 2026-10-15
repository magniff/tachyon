# c-mixed-build: a tachyon program and a C file, linked into one executable.
#
#   make                 # builds ./c-mixed-build
#   make run             # and runs it on a few readings
#   make TACHYONC=tachyonc   # a tachyonc on the PATH instead of the tree's

TACHYONC ?= ../../target/tachyonc
CC ?= cc

c-mixed-build: main.o ring.o
	$(CC) main.o ring.o -o $@

# The C view of the tachyon program: on_evict and EVICTIONS, for ring.c.
main.h: main.tach
	$(TACHYONC) --emit-header main.tach -o $@

ring.o: ring.c ring.h main.h
	$(CC) -O2 -c ring.c -o $@

# main.tach imports ring.h: it is rebuilt when the header changes.
main.o: main.tach ring.h
	$(TACHYONC) main.tach -o $@

run: c-mixed-build
	echo 10 20 30 40 55 15 60 5 25 | ./c-mixed-build

clean:
	rm -f c-mixed-build main.o ring.o main.h

.PHONY: run clean
