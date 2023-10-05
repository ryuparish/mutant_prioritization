# Installation Instructions
The recommended way of using this artifact is via the provided Docker container.
The Docker container is based on the ubuntu:20.04 image base
(sha256:57df66b9fc9ce2947e434b4aa02dbe16f6685e20db0c170917d4a1962a5fe6a9).

To load the provided Docker container, run the following command in the
artifact’s root directory:
```sh
gunzip -c docker_image.tar.gz | docker load
```

(To build the image yourself, run `docker build -t samkaufman/custmut:latest .`
in the `code` subdirectory.)

Run the following command to test whether the Docker container has been
successfully loaded:
```sh
docker run -it samkaufman/custmut:latest ls
```

The output should be:
```text
Dockerfile  Makefile   data_analysis    deps
LICENSE     README.md  data_collection  init.sh
```
