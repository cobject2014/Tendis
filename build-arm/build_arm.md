1. This  repo is Tendis , github link: https://github.com/Tencent/Tendis
2. Tendis is a Redis like service, and support X86/x64.
3. Currently officially there is no ARM support,so our task is make a ARM build
4. There are discussion about how to make this ARM build:
   1. https://github.com/Tencent/Tendis/issues/281
   2. https://github.com/Tencent/Tendis/issues/75
   3. https://github.com/Tencent/Tendis/issues/270
5. Based on these discussion we make a "Dockerfile" try to build ARM version Tendis.
6. Our current work env is Mac OS, which is also ARM64 arch.
7. Your task is use this Dockerfile as a blue print and build an ARM version tendis.
8. For all verified change make the build go ahead, please log it to "verified_change.txt"
