sudo mkdir /usr/share/jupyter/kernels/d
sudo cp ./kernel.json /usr/share/jupyter/kernels/d
dub build
sudo cp ./jupyterd /usr/sbin
