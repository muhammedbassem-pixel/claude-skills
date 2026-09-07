# OWASP Threat Dragon model schema (v2.6.2)

The `.json` model can be edited in Threat Dragon (Step 4) or authored by hand. Structure:

```jsonc
{
  "version": "2.6.2",
  "summary": { "title": "", "owner": "", "description": "", "id": 0 },   // id: integer
  "detail": {
    "contributors": [ { "name": "" } ],
    "diagramTop": 1,          // integer
    "threatTop": 0,           // integer: highest threat counter used
    "reviewer": "",
    "diagrams": [ {
      "id": 0,                // integer
      "title": "",
      "diagramType": "STRIDE",
      "placeholder": "",
      "thumbnail": "./public/content/images/thumbnail.stride.jpg",
      "version": "2.6.2",
      "cells": [ /* nodes + edges, flat array */ ]
    } ]
  }
}
```

## Cell shapes → `data.type`

| `shape` | `data.type` | role |
|---------|-------------|------|
| `actor` | `tm.Actor` | external entity |
| `process` | `tm.Process` | process |
| `store` | `tm.Store` | data store |
| `flow` | `tm.Flow` | data flow (edge) |
| `trust-boundary-box` | `tm.BoundaryBox` | trust boundary (box) |
| `td-text-block` | `tm.Text` | annotation |

`trust-boundary-curve` (a line) is also supported; the box variant is shown here.

## Node cell (actor / process / store)

```jsonc
{
  "position": { "x": 60, "y": 170 },
  "size": { "width": 160, "height": 80 },
  "attrs": {},                 // styling — Threat Dragon fills defaults; can be {}
  "visible": true,
  "shape": "process",
  "zIndex": 3,
  "ports": { "groups": { "top": {}, "right": {}, "bottom": {}, "left": {} },
             "items": [ { "group": "top", "id": "<uuid>" } ] },
  "id": "<uuid>",
  "data": {
    "type": "tm.Process",
    "name": "Backend Service",
    "description": "",
    "outOfScope": false,
    "reasonOutOfScope": "",
    "hasOpenThreats": false,
    "threats": []              // see Threat below
  }
}
```

Per-shape `data` extras:
- **actor**: `providesAuthentication` (bool)
- **process**: `handlesCardPayment`, `handlesGoodsOrServices`, `isWebApplication`, `privilegeLevel`
- **store**: `isALog`, `isEncrypted`, `isSigned`, `storesCredentials`, `storesInventory`

## Edge cell (flow)

```jsonc
{
  "shape": "flow",
  "attrs": {},
  "width": 200, "height": 100,
  "zIndex": 10,
  "connector": "smooth",
  "data": {
    "type": "tm.Flow",
    "name": "Browser → API",
    "description": "",
    "outOfScope": false,
    "isTrustBoundary": false,
    "reasonOutOfScope": "",
    "hasOpenThreats": false,
    "isBidirectional": false,
    "isEncrypted": true,
    "isPublicNetwork": true,
    "protocol": "HTTPS",
    "trustBoundaryIds": [],
    "threats": []
  },
  "labels": [ { "attrs": { "label": { "text": "Browser → API" } }, "position": 0.5 } ],
  "id": "<uuid>",
  "source": { "cell": "<node-uuid>" },
  "target": { "cell": "<node-uuid>" },
  "vertices": []
}
```

## Trust boundary box

```jsonc
{
  "shape": "trust-boundary-box",
  "zIndex": -1,
  "position": {"x":0,"y":0}, "size": {"width":400,"height":300},
  "id": "<uuid>",
  "data": {
    "type": "tm.BoundaryBox",
    "name": "PetroApp-Owned Systems",
    "description": "",
    "isTrustBoundary": true,
    "hasOpenThreats": false,
    "containedElements": [ "<node-uuid>" ],   // nodes inside
    "crossingFlows": [ "<flow-uuid>" ]         // flows crossing
  }
}
```

## Threat (on a cell's `data.threats[]`)

```jsonc
{
  "status": "Open",                 // Open | Mitigated | Open (N/A)
  "severity": "High",               // High | Medium | Low
  "title": "No certificate pinning on mobile client",
  "type": "Information disclosure", // STRIDE: Spoofing | Tampering | Repudiation |
                                    //   Information disclosure | Denial of service |
                                    //   Elevation of privilege
  "description": "...",
  "mitigation": "...",
  "modelType": "STRIDE",
  "id": "<uuid>"
}
```

Set the owning cell's `data.hasOpenThreats` to `true` when it has any `Open` threat, and bump
`detail.threatTop` to the number of threats created. Generate UUIDs for cell/threat/port `id`s
(`uuidgen | tr 'A-Z' 'a-z'`).
