# core-wire: A tool/library to make CWL engines connected to remote resources
[![release](https://badgen.net/github/release/tom-tan/core-wire)](https://github.com/tom-tan/core-wire/releases/latest)
[![license](https://badgen.net/github/license/tom-tan/core-wire)](https://github.com/tom-tan/core-wire/blob/main/LICENSE)
[![CI](https://github.com/tom-tan/core-wire/actions/workflows/ci.yml/badge.svg)](https://github.com/tom-tan/core-wire/actions/workflows/ci.yml)

The [CWL specification](https://www.commonwl.org/v1.2/CommandLineTool.html#File) requires the workflow engines to support the URIs with the `file` scheme but supporting other schemes such as `https`, `ftp`, and `s3` is optional.
Therefore, using such optional schemes in the input objects prevents portability between workflow engines.

The core-wire aims to fix this problem by providing a way to download/upload files and directories in a given input object
and returns a new input object with downloaded/uploaded URIs.

## Usage
```console
$ core-wire input.yaml file:///uri/to/the/destination
```
It accepts YAML and JSON files for the input object.

See `core-wire -h` for details.

### Example: get remote resources
- It currently supports `file`, `http`, `https`, and `ftp` schemes by default.
  - Limitation: The `ftp` scheme requires the `curl` command. It will be fixed in the future release.
```console
$ cat input.json
{
    "param1": 10,
    "param2": {
        "class": "File",
        "location": "https://remote/resource/file.txt"
    }
}
$ core-wire input.json file:///current-dir/inp
{
    "param1": 10,
    "param2": {
        "class": "File",
        "location": "file:///current-dir/inp/file.txt",
        "path": "/current-dir/inp/file.txt",
        "basename": "file.txt",
        "dirname": "/current-dir/inp",
        "nameroot": "file",
        "nameext": ".txt"
        "checksum": "sha1$47a013e660d408619d894b20806b1d5086aab03b",
        "size": 13
    }
}
$ ls inp
file.txt
```

### Example: put local resources
**Note**: not yet implemented

```console
$ cat input.json
{
    "param1": 10,
    "param2": {
        "class": "File",
        "location": "file:///current-dir/inp/efa951dd-df01-4ce9-0008-39e7dbe25d6a/file.txt",
        "path": "/current-dir/inp/efa951dd-df01-4ce9-0008-39e7dbe25d6a/file.txt",
        "basename": "file.txt",
        "dirname": "/current-dir/inp/efa951dd-df01-4ce9-0008-39e7dbe25d6a",
        "nameroot": "file",
        "nameext": ".txt"
        "checksum": "sha1$47a013e660d408619d894b20806b1d5086aab03b",
        "size": 13
    }
}
$ core-wire --config=s3conf.json input.json s3://bucket/inp/
{
    "param1": 10,
    "param2": {
        "class": "File",
        "location": "s3://bucket/inp/e2949107-f856-2417-ce6c-1030af43f9ea/file.txt"
        "basename": "file.txt",
        "nameroot": "file",
        "nameext": ".txt"
        "checksum": "sha1$47a013e660d408619d894b20806b1d5086aab03b",
        "size": 13
    }
}
```

## Extending supported schemes
You can extend schemes by specifying the commands to download files and directories with `--inline-dl-file-cmd` and `--inline-dl-dir-cmd`.

The accepted value is as follows:
```
$scheme:$command
```
- `$scheme` is a URI scheme such as `ssh` and `s3`. You can also override the default schemes.
- `$command` is a command to download a file or a directory from a URI with a given scheme.
  - Example: `curl -f <src-uri> -o <dst-path>`
  - The `<src-uri>` and `<src-path>` is replaced with a source URI or path of a file or a directory.
  - The `<dst-uri>` and `<dst-path>` is replaced with a destination URI or path of a file or a directory.

Here is a concrete example:
```console
$ cat input.json
{
    "param1": 10,
    "param2": {
        "class": "File",
        "location": "ssh:///remote-server:/home/user/path-to/file.txt",
    }
}
$ core-wire input.json file:///current-dir/inp --inline-dl-file-cmd=ssh:"scp <src-uri> <dst-path>"
{
    "param1": 10,
    "param2": {
        "class": "File",
        "location": "file:///current-dir/inp/file.txt",
        "path": "/current-dir/inp/file.txt",
        "basename": "file.txt",
        "dirname": "/current-dir/inp",
        "nameroot": "file",
        "nameext": ".txt"
        "checksum": "sha1$47a013e660d408619d894b20806b1d5086aab03b",
        "size": 13
    }
}
```

There is a limitation of the extended schemes:
- When `--inline-dl-file-cmd` is specified but `--inline-dl-dir-cmd` is not, `core-wire` rejects non-literal directory objects (i.e., only accept directory objects with the `listing` field).
  - If you have to handle non-literal directory objects, specify `--inline-dl-dir-cmd` in addition to `--inline-dl-file-cmd`.
