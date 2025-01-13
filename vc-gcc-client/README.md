# Varnish Cache Command Compiler Client

A Go-based client for compiling Varnish Cache (VCL) commands into shared objects
(.so files) using a remote compilation service. This tool is designed to work as
a `cc_command` parameter in Varnish Cache configurations.

## Overview

This client sends the Varnish generated .c file to a remote compilation service and
receives compiled shared object that can be used by Varnish. It handles
the compilation process through a HTTP REST interface, making it potentially
suitable for environments where local compilation is not desired or possible.

## Usage

```bash
vcc-client <input.c> <output.so>
```

### Environment Variables

- `VS_GCC_SERVER`: URL of the compilation service (default: `http://localhost:8080`)

## Configuration with Varnish Cache

Add the following to your Varnish configuration:

```vcl
parameter cc_command = "/path/to/vcc-client %s %s";
```

## API Communication

The client communicates with the compilation service using multipart/form-data:

- **Endpoint**: `/compile`
- **Method**: POST
- **Content-Type**: multipart/form-data
- **Form Field**: source (containing the C source code)

### Response Format

```json
{
    "success": true|false,
    "error": "error message if compilation failed",
    "binary": "base64 encoded compiled binary"
}
```
