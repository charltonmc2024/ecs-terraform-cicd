## QA Environment Specifications

| # | Server Name | Usage | Specs (vCore / GB RAM / SSD) | Description |
|---|---|---|---|---|
| 01 | District-Teacher-Student-MongoDB-Archives (DB) | Database | 4 / 8 / 240 (L) | Archiving Student/Teacher Profile |
| 02 | CDN/Image Server (Storage) | Storage | 2 / 4 / 120 (M) | Image Server |
| 03 | Mail-Host-Server (API) | Services | 4 / 8 / 240 (L) | Mail Server |
| 04 | Erudition-Analytics (API) | Services | 4 / 8 / 240 (L) | Analytics APIs |
| 05 | API-Gateway-Server | Gateway | 4 / 8 / 240 (L) | Student-Teacher API Gateway |
| 06 | Teacher-Student-Redis-Server | Queue | 8 / 16 / 480 (XL) | For Teacher-Student-MongoDB |
| 07 | Teacher-Student-MongoDB (DB) | Database | 4 / 8 / 240 (L) | Teacher-Student-MongoDB |
| 08 | Teacher-Student-Bulk-Upload (APIs) | Services | 4 / 8 / 240 (L) | Teacher-Student-Bulk-Upload APIs |
| 09 | Admin-Staff-Client-Server | Client / Services | 12 / 24 / 720 (XXL) | Admin-Staff Monolith |
| 10 | Admin-Staff-MongoDB | Database | 4 / 8 / 240 (L) | Admin-Staff Database |
| 11 | Teacher-Student-Client | Client | 1 / 1 / 10 (XS) | Teacher-Student-Client |

## Proposals

| # | Server Name | Usage | Specs (vCore / GB RAM / SSD) | Description |
|---|---|---|---|---|
| 12 | Admin-Staff-Redis-Server | TBD | TBD | TBD |
| 13 | District-Teacher-Student-MongoDB-Archives-Redis-Server | TBD | TBD | TBD |