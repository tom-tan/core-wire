# core-wire: A tool/library to make CWL engines connected to remote resources
[![CI](https://github.com/tom-tan/core-wire/actions/workflows/ci.yml/badge.svg)](https://github.com/tom-tan/core-wire/actions/workflows/ci.yml)
[![license](https://badgen.net/github/license/tom-tan/core-wire)](https://github.com/tom-tan/core-wire/blob/main/LICENSE)

## Usage

**Note**: not yet implemented

### Example: get remote resources
```console
$ cat input.json
{
    "param1": 10,
    "param2": {
        "class": "File",
        "location": "https://remote/resource/file.txt"
    }
}
$ core-wire input.json --dest=file:///current-dir/inp
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
$ ls inp/efa951dd-df01-4ce9-0008-39e7dbe25d6a
file.txt
```

### Example: put local resources
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
$ core-wire --config=s3conf.json input.json --dest=s3://bucket/inp/
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
