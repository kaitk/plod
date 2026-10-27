// error: plod needs the package hash
// A program that imports plod.jwt must declare goose-hash, for HMAC-SHA-256,
// in its root file.
import std;
import http from "github.com/kaitk/goose-http@v0.5.12";
import plod from "../../";
import plod.jwt;

fn main() {}
