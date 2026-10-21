#!/bin/sh
# Builds main.tach with tachyonc; every *.tach here.
tachyonc main.tach -o prog && ./prog
ls geo/*.tach
