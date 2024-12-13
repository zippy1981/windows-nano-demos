# Node and PHP development windows nano server development container

Node and PHP actually work. A text editor caleld micro is available

Vite composer, and the laravel are installed and in your path.

Available at <https://hub.docker.com/repository/docker/zippy1981/windows-nano-php/general>.

## Building

To build a 2022 container:

> ./build.ps1

To build the windwos 2019 container:

From powershell

```pwsh
$env:WINDOWS_VERSION=2019
./build.cmd
```

# Running

> docker run -ti zippy1981/windows-nano-php:2019 cmd