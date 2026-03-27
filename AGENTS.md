# Tendis ARM fork

## Tendis 

[Tendis Github](https://github.com/Tencent/Tendis)


Tendis is a high-performance distributed storage system which is fully compatible with the Redis protocol

## ARM fork
Tendis has not officially support ARM arch. So this fork is make Tendis work with ARM platform.

## How it works

The major work is in `build-arm/Dockerfile`, which patch source code to make it work on ARM arch.

## Tests
This fork leverage existing test sutie, but port to ARM. The bulid/test process is also using Docker env. Check `build-arm/Dockerfile.test`

## Others

Read `build-arm/readme.md` and `build-arm/build_arm.md` for more information.

## Log

For all important actions, please log to `.agents/log` folder, the file name should be "YYYY-mm-dd.log".