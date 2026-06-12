# ft_warp

Work on your 42 projects from your machine, but in the same 42 campus environment.

## Requirements

Docker.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/pruiz-ca/ft_warp/main/install.sh | sh
```

This installs an `ft_warp`/`ftw` command into `~/.local/bin` (make sure that folder is
on your `PATH`). The image downloads itself the first time you run the command.

## Usage

Run it from inside any project folder. The folder is mounted into the container,
so files you change on either side stay in sync and stay owned by your user.

```sh
ft_warp                 # open a shell in your project
ft_warp make            # build with the campus compiler
ft_warp norminette .    # run norminette
ft_warp gdb ./program
ft_warp valgrind ./program
ft_warp doctor          # check your setup and report problems
```

`ftw` is a shorthand for `ft_warp`.

To reach a server running inside the container from your browser, publish its
ports with `-p` (comma separated) and bind the server to `0.0.0.0` inside:

```sh
ftw -p 8080 python -m http.server 8080 --bind 0.0.0.0   # open http://localhost:8080
ftw -p 8080,4443 ./webserv conf/default.conf
```

A bare port like `8080` is published on localhost only. The `host:container` and
`addr:host:container` forms are passed straight to Docker.

## The two images

```sh
ft_warp --core    # C, C++, Python, norminette, gdb, valgrind
ft_warp --full    # everything in core, plus graphics (MLX42), Rust and lldb/llvm
```

Plain `ft_warp` uses the full image if you have it, otherwise core. The first
time, it asks which one to download.

When you open a shell, a short banner shows which image and version you are in.
You can also check with `cat /etc/ft_warp-release`.

Once a day, `ft_warp` checks whether a newer image exists and asks before
pulling it. `ft_warp update` pulls the latest of whatever images you already
have. `ft_warp --help` lists everything.

## Project defaults (.ftwrc)

Drop a `.ftwrc` file in a project to set its defaults. Command line flags
override it.

```ini
VARIANT=full
PORTS=8080,4443:443
```

With that file, plain `ft_warp` in the project runs the full image and publishes
those ports.

## Graphical projects

```sh
ft_warp --full ./cub3D maps/map.cub
```

On Linux this works out of the box. On macOS the installer sets up XQuartz and
PulseAudio for you; open XQuartz before you run a graphical project.

## VS Code

Copy [`examples/.devcontainer/devcontainer.json`](examples/.devcontainer/devcontainer.json)
into your project and run "Dev Containers: Reopen in Container". You get the
campus environment inside your editor, with working clangd IntelliSense, gdb and
norminette.

## Notes

- The container runs as your own user, so files stay owned by your user.
- Images are `linux/amd64` to match the campus. On Apple Silicon they run emulated.
- pip, cargo and ccache caches persist between runs in a Docker volume, so
  repeated builds are fast.

## License

[MIT](LICENSE)
