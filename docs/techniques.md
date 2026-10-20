# Techniques

Frozen values are positional. The schema stays in the program. Dict keys are sorted by their UTF-8 bytes so two encodes of the same mapping match. Floats keep every bit, including the sign of zero and the payload of a NaN.

The tensor directory is one Frozen value. Its magic is `KLNT` and its version byte is 2. Descriptors are fixed width. Payloads start on a 64-byte boundary measured from the start of the directory. Decode borrows those bytes from the caller's buffer. `Tensor.data` copies them out when the caller asks for an owned array.

A count is checked against the unread bytes before Kiln allocates storage for the elements. The default cap is 16,777,216 counts and 16 MiB for one string or byte run. Pass `cap:` to raise it. Nesting deeper than 64 containers is `LIMIT`.

A frame is sixteen bytes: `KLN0`, four zero bytes, and the FNV-1a 64 hash of the canonical type text, then one Frozen value. A hash that does not match the schema the caller passed is `SCHEMA`. `typeHash` computes that hash. The token for a tensor field is the ASCII bytes `tensors`.

`Writer.encode` resets the length and keeps the existing storage. Call it in a loop when the same process encodes many records. Numeric list bodies and tensor payloads are copied in bulk. Field names on a struct are not reallocated; the schema already owns those strings.

`bash scripts/run-microbench.sh` prints nanoseconds for a small struct batch and for one 1024-element `f32` tensor, encode and decode.
