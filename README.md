This git-project is a helper project to be able to build U-Boot, TF-A, Linux
kernel etc as standalone components for iMX8MQ-evk boards. I.e., with this you
don't have to use Yocto etc.

Setup
=====
1. Clone this git project
2. $ make setup
3. $ make -j2 toolchains

Compile
=======
1. $ make

Flash
=====
1. $ make flash
2. Follow the instructions for the "dd" command

// Joakim Bech
2020-08-28

