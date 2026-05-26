# FMSPC Async Upsert V2 Notes

This note records the current V2 async FMSPC TCB info design, its tradeoffs, and the
places that are likely to need future gas work if Intel PCS TCB info keeps growing.

## Current Flow

The current V2 flow keeps the old external goal: store parsed TCB data and preserve
the signed Intel JSON semantics used by quote verification. The implementation now
builds both representations from one typed upload stream instead of uploading raw
JSON chunks and then separately uploading parsed data.

1. `startAsyncUpsert` initializes one pending update, stores the ref id, signature,
   expected raw JSON length, and allocates the pending builder state.
2. `uploadBasicInfo` uploads the fixed top-level `tcbInfo` fields such as `id`,
   `version`, `issueDate`, `nextUpdate`, `fmspc`, `pceId`, `tcbType`, and
   `tcbEvaluationDataNumber`. The QPL tool supplies typed ABI data plus layout
   indexes describing where each key/value pair appears in the minified Intel JSON.
3. `uploadTcbLevelsBatch` uploads one or more typed TCB levels. The QPL tool also
   supplies layout descriptors so the contract can write the corresponding raw JSON
   fragment while storing the parsed level data. SGX component metadata fields such
   as `category` and `type` are included in the descriptor path, and per-level layout
   overrides are supported when a level does not match the batch header layout.
4. `uploadTdxModuleIdentitiesBatch` does the same for TDX module identities and their
   nested TCB levels.
5. `finalizeAsyncUpsert` checks the reconstructed raw JSON against the Intel
   signature, computes the same content hash semantics as the current reader path,
   finalizes DAO references, and clears the pending update.

The flow assumes Intel PCS returns minified JSON. Whitespace is therefore not modeled
as user-controllable layout.

## Upload Method Examples

The examples below show the decoded meaning of the QPL payloads. On-chain, the
payloads are compact `bytes` values, not ABI-encoded Solidity structs. QPL computes
byte offsets, object order descriptors, and packed values from the minified Intel PCS
response, then calls the upload methods in order.

Order descriptors are 1-based positions. A zero means the field is omitted. For
example, a top-level order byte array of `[1,2,3,4,5,6,7,8,0,0,9]` means:

- `id` is the first top-level field.
- `version` is second.
- `tdxModule` and `tdxModuleIdentities` are absent.
- `tcbLevels` is ninth.

The raw JSON stored by async upsert is the inner `tcbInfo` object string, not the outer
`{"tcbInfo":...,"signature":"..."}` wrapper. `startAsyncUpsert` receives the outer
signature and the byte length of that inner `tcbInfo` string.

### SGX Example

Assume Intel returns this minified SGX `tcbInfo` object. The component arrays are
shortened here for readability; real Intel v3/v4 data has 16 SGX component entries,
and QPL sends 16 component descriptors and 16 SVN bytes.

```json
{"id":"SGX","version":3,"issueDate":"2026-05-20T16:02:04Z","nextUpdate":"2026-06-19T16:02:04Z","fmspc":"00606A000000","pceId":"0000","tcbType":0,"tcbEvaluationDataNumber":19,"tcbLevels":[{"tcb":{"sgxtcbcomponents":[{"svn":1,"category":"BIOS","type":"Microcode"},{"svn":1,"category":"BIOS","type":"Microcode"}],"pcesvn":7},"tcbDate":"2025-11-12T00:00:00Z","tcbStatus":"UpToDate"},{"tcb":{"sgxtcbcomponents":[{"svn":1,"category":"BIOS","type":"Microcode"},{"svn":0,"category":"BIOS","type":"Microcode"}],"pcesvn":6},"tcbDate":"2024-08-14T00:00:00Z","tcbStatus":"OutOfDate","advisoryIDs":["INTEL-SA-00001"]}]}
```

The QPL call sequence is:

```text
startAsyncUpsert(refId, signature, rawLength)
uploadBasicInfo(refId, basicPayload, topLevelOrder)
uploadTcbLevelsBatch(refId, 0, 2, levelsPayload)
finalizeAsyncUpsert(attestationId, refId)
```

`uploadBasicInfo` stores parsed basic fields and writes the top-level raw JSON
segments. In decoded form, this call carries:

```text
topLevelOrder = [1,2,3,4,5,6,7,8,0,0,9]

basicPayload:
  offsets:
    id: byte offset of "id"
    version: byte offset of "version"
    issueDate: byte offset of "issueDate"
    nextUpdate: byte offset of "nextUpdate"
    fmspc: byte offset of "fmspc"
    pceId: byte offset of "pceId"
    tcbType: byte offset of "tcbType"
    tcbEvaluationDataNumber: byte offset of "tcbEvaluationDataNumber"
    tdxModule: 0
    tdxModuleIdentities: 0
    tcbLevels: byte offset of "tcbLevels"
  tcbLevelsArrayStart: byte offset just after the opening tcbLevels bracket
  tcbLevelsArrayEnd: byte offset just after the closing tcbLevels bracket
  tcbLevelsCount: 2
  tdxIdentitiesCount: 0
  levelsStreamLength: packed byte length for the two TCB levels
  identitiesStreamLength: 0
  id: SGX
  version: 3
  issueDateRaw: "2026-05-20T16:02:04Z"
  nextUpdateRaw: "2026-06-19T16:02:04Z"
  fmspcHex: "00606A000000"
  pceidHex: "0000"
  tcbType: 0
  evaluationDataNumber: 19
  hasTdxModule: false
```

After this call, the raw buffer already contains `{`, `}`, all basic key/value
segments, and the empty `tcbLevels` array brackets. The actual level objects are still
missing and will be filled by `uploadTcbLevelsBatch`.

For `uploadTcbLevelsBatch(refId, 0, 2, levelsPayload)`, QPL sends one shared SGX
component layout header plus two decoded level items:

```text
levelsPayload header:
  hasTdxComponents: false
  sgxComponentLayout[16]:
    each descriptor has:
      order for svn/category/type inside the component object
      category bytes, for example "BIOS"
      type bytes, for example "Microcode"

level[0]:
  byteStart, byteEnd: raw byte range of the first level object
  levelOrder: [1,2,3,0]        # tcb, tcbDate, tcbStatus, advisoryIDs omitted
  tcbOrder: [1,2,0]            # sgxtcbcomponents, pcesvn, tdxtcbcomponents omitted
  flags: 0
  sgxSvns: 16 SVN bytes
  pcesvn: 7
  tcbDateRaw: "2025-11-12T00:00:00Z"
  status: UpToDate
  advisoryIds: []

level[1]:
  byteStart, byteEnd: raw byte range of the second level object
  levelOrder: [1,2,3,4]        # advisoryIDs is present
  tcbOrder: [1,2,0]
  flags: HAS_ADVISORY_FIELD
  sgxSvns: 16 SVN bytes
  pcesvn: 6
  tcbDateRaw: "2024-08-14T00:00:00Z"
  status: OutOfDate
  advisoryIds: ["INTEL-SA-00001"]
```

The helper rebuilds the two raw level objects and the legacy packed level stream from
this single payload. The DAO writes one raw chunk into the reserved raw JSON ref and
one packed stream chunk into the levels ref, then advances `parsedLevels` from `0` to
`2`.

There is no `uploadTdxModuleIdentitiesBatch` call for SGX because `id` is SGX and
`tdxModuleIdentities` is omitted.

### TDX Example

Assume Intel returns this minified TDX `tcbInfo` object. The SGX/TDX component arrays
are again shortened for readability; real payloads carry 16 entries for each component
array.

```json
{"id":"TDX","version":3,"issueDate":"2026-05-21T04:14:29Z","nextUpdate":"2026-06-20T04:14:29Z","fmspc":"00806F050000","pceId":"0000","tcbType":0,"tcbEvaluationDataNumber":19,"tdxModule":{"mrsigner":"00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF","attributes":"0000000000000000","attributesMask":"FFFFFFFFFFFFFFFF"},"tdxModuleIdentities":[{"id":"TDX_01","mrsigner":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","attributes":"0000000000000000","attributesMask":"FFFFFFFFFFFFFFFF","tcbLevels":[{"tcb":{"isvsvn":1},"tcbDate":"2025-10-01T00:00:00Z","tcbStatus":"UpToDate"}]}],"tcbLevels":[{"tcb":{"sgxtcbcomponents":[{"svn":1,"category":"BIOS","type":"Microcode"},{"svn":1,"category":"BIOS","type":"Microcode"}],"pcesvn":7,"tdxtcbcomponents":[{"svn":1,"category":"TDX","type":"Module"},{"svn":1,"category":"TDX","type":"Module"}]},"tcbDate":"2025-11-12T00:00:00Z","tcbStatus":"UpToDate"}]}
```

The QPL call sequence is:

```text
startAsyncUpsert(refId, signature, rawLength)
uploadBasicInfo(refId, basicPayload, topLevelOrder)
uploadTcbLevelsBatch(refId, 0, 1, levelsPayload)
uploadTdxModuleIdentitiesBatch(refId, 0, 1, identitiesPayload)
finalizeAsyncUpsert(attestationId, refId)
```

`uploadBasicInfo` carries the same basic fields as SGX plus TDX module metadata and
TDX identity ranges:

```text
topLevelOrder = [1,2,3,4,5,6,7,8,9,10,11]
moduleOrder = [1,2,3]          # mrsigner, attributes, attributesMask

basicPayload:
  tcbLevelsCount: 1
  tdxIdentitiesCount: 1
  hasTdxModule: true
  tdxModuleObjStart, tdxModuleObjEnd: raw range of the tdxModule object
  tdxIdentitiesArrayStart, tdxIdentitiesArrayEnd: raw range of the identity array
  levelsStreamLength: packed byte length for one top-level TCB level
  identitiesStreamLength: packed byte length for one module identity
  id: TDX
  version: 3
  issueDateRaw: "2026-05-21T04:14:29Z"
  nextUpdateRaw: "2026-06-20T04:14:29Z"
  fmspcHex: "00806F050000"
  pceidHex: "0000"
  tcbType: 0
  evaluationDataNumber: 19
  moduleMrsignerHex: 96 hex chars
  moduleAttributesHex: "0000000000000000"
  moduleAttributesMaskHex: "FFFFFFFFFFFFFFFF"
```

For the top-level TDX TCB level, `uploadTcbLevelsBatch` sends both SGX and TDX
component layouts:

```text
levelsPayload header:
  hasTdxComponents: true
  sgxComponentLayout[16]
  tdxComponentLayout[16]

level[0]:
  levelOrder: [1,2,3,0]
  tcbOrder: [1,2,3]            # sgxtcbcomponents, pcesvn, tdxtcbcomponents
  flags: 0
  sgxSvns: 16 SVN bytes
  tdxSvns: 16 SVN bytes
  pcesvn: 7
  tcbDateRaw: "2025-11-12T00:00:00Z"
  status: UpToDate
```

If one level has component metadata order or category/type values that differ from the
batch header, QPL sets the per-level layout override flag and includes the override
descriptor for that level. This avoids rejecting a valid Intel PCS response because a
batch-level layout assumption did not hold.

For `uploadTdxModuleIdentitiesBatch`, QPL sends one identity item:

```text
identity[0]:
  byteStart, byteEnd: raw byte range of the identity object
  identityOrder: [1,2,3,4,5]   # id, mrsigner, attributes, attributesMask, tcbLevels
  idRaw: "TDX_01"
  mrsignerHex: 96 hex chars
  attributesHex: "0000000000000000"
  attributesMaskHex: "FFFFFFFFFFFFFFFF"
  nestedLevels:
    nestedLevel[0]:
      levelOrder: [1,2,3,0]
      flags: 0
      isvsvn: 1
      tcbDateRaw: "2025-10-01T00:00:00Z"
      status: UpToDate
      advisoryIds: []
```

The DAO writes the rebuilt raw identity object into the reserved raw JSON ref, writes
one packed identity record into the identities stream ref, and advances
`parsedModuleIdentities` from `0` to `1`.

### Batch Splitting Example

For a large SGX response with 15 levels and the default QPL batch size of 3, QPL calls:

```text
uploadTcbLevelsBatch(refId, 0, 3, payloadForLevels0To2)
uploadTcbLevelsBatch(refId, 3, 3, payloadForLevels3To5)
uploadTcbLevelsBatch(refId, 6, 3, payloadForLevels6To8)
uploadTcbLevelsBatch(refId, 9, 3, payloadForLevels9To11)
uploadTcbLevelsBatch(refId, 12, 3, payloadForLevels12To14)
```

The DAO requires `start == parsedLevels`, so batches must be uploaded in order. The
same rule applies to TDX module identities through `parsedModuleIdentities`.

## Strengths

- Raw JSON and parsed storage are produced from the same typed upload, so the old
  duplicate "raw chunk upload plus parsed upload" path is gone.
- JSON field order can vary because QPL passes layout indexes instead of relying on
  hardcoded Solidity concatenation order.
- The contract avoids expensive `bytes.concat` reconstruction. The pending raw JSON
  buffer is allocated to the expected size and filled by upload steps.
- Upload batches now write one raw chunk and one packed stream chunk per batch instead
  of many small storage writes.
- Per-write debug events were removed from the hot path.
- Final raw slicing uses a preallocated word-copy path while keeping the current
  content hash semantics unchanged.
- The public V2 ABI no longer keeps the older V2 comparison implementation, since no
  production deployment needs backward compatibility for that removed async variant.

## Tradeoffs

- QPL now owns more of the Intel JSON parsing and layout construction. This is the
  right side of the boundary for gas, but it means QPL and the contract ABI must stay
  in lockstep.
- Only known Intel PCS fields are represented. If Intel adds fields that must become
  part of stored typed data or content-hash semantics, QPL and contracts need an ABI
  update.
- Key strings are still hardcoded on-chain so the contract can rebuild the signed
  JSON. Values and key ordering remain dynamic.
- The final signature and content-hash checks are still one transaction.

## Growth Limits

Most upload work can be split by lowering the QPL async parse batch size:

- `uploadTcbLevelsBatch` can go down to one TCB level per transaction.
- `uploadTdxModuleIdentitiesBatch` can go down to one module identity per transaction.

However, the implementation is not infinitely splittable. The first likely
non-splittable bottlenecks are:

- `finalizeAsyncUpsert`: this is a single transaction that reads the reconstructed raw
  JSON, validates the Intel signature, slices the final raw payload, computes/stores
  content hashes, finalizes references, and clears the pending update.
- A single very large TCB level: if one level contains enough advisory IDs or component
  metadata, `uploadTcbLevelsBatch` with one item can still exceed the block gas limit.
- A single very large TDX module identity: nested levels inside one module identity are
  not independently splittable in the current ABI.
- Read/verification reconstruction: `_buildFinalPayload` and the stream-to-bytes read
  path are not upload transactions, but they are still monolithic call-time work.

Based on the current known PCS fixtures and earlier E2E gas logs, the conservative
warning line for `finalizeAsyncUpsert` is about 45 KB of inner `tcbInfo` JSON. The
current word-copy optimization should improve that threshold, but 45 KB remains a
useful operational alert threshold until a fresh large-fixture profile replaces it.
For SGX data shaped like the current largest fixtures, that is roughly in the range of
80 to 90 TCB levels.

## Future Optimization Directions

- Reuse the already-computed raw SHA-256 hash during signature validation so finalize
  does not hash the same raw bytes more than necessary.
- Add a staged or chunked finalize path if Intel PCS data approaches the conservative
  45 KB warning line.
- Split TDX module identity nested TCB levels if Intel starts returning much larger
  module identity sections.
- Consider a future versioned content hash based on typed/incremental commitments.
  This would be a semantic change and should be introduced only with an explicit new
  version, not as a silent V2 gas optimization.
- Add a typed read interface or cached final payload pieces if verification-side
  reconstruction becomes the dominant call cost.
- Continue profiling storage packing in parsed TCB level and module identity writes,
  especially for arrays with many short string fields.

## E2E Coverage Expectations

Targeted E2E should cover:

- SGX deploy -> async upsert -> verify on a Story Aeneid Anvil fork.
- TDX deploy -> async upsert -> verify on a Story Aeneid Anvil fork.
- Same-FMSPC double upsert where a second, different signed Intel response overwrites
  the first result.
- Full SGX/TDX FMSPC regression for evaluation data versions 19, 20, and 21 before
  release, but that suite is intentionally kept separate from quick targeted checks.
