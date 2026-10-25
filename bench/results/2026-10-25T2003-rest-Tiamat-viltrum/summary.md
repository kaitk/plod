## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| viltrum | A | serialize | 228.7K | 226.8K-229.7K | 1.05 | 3.65 | 16.6 | 65 | 0 |
| viltrum | A | template | 374.0K | 372.2K-384.1K | 0.63 | 1.68 | 10.6 | 57 | 0 |
| viltrum | B | serialize | 51.0K | 50.9K-52.5K | 4.20 | 11.7 | 64.1 | 147 | 0 |
| viltrum | B | template | 182.0K | 181.6K-186.8K | 1.16 | 53.4 | 18.7 | 927 | 0 |
| viltrum | C | serialize | 2.3K | 2.3K-2.4K | 105 | 245 | 1658.2 | 583 | 0 |
| viltrum | C | template | 11.4K | 11.4K-11.5K | 21.7 | 50.1 | 328.7 | 508 | 0 |

## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| viltrum | A | serialize | item | 77.8K-77.9K of 78.0K | 0.12 | 0.99-2.56 | 0 |
| viltrum | A | serialize | me | 16.0K of 16.0K | 0.11 | 0.95-2.51 | 0 |
| viltrum | A | serialize | write | 6.0K of 6.0K | 0.12 | 0.95-2.47 | 0 |
| viltrum | A | template | item | 77.8K of 78.0K | 0.10 | 0.18-0.19 | 0 |
| viltrum | A | template | me | 16.0K of 16.0K | 0.09-0.10 | 0.17-0.18 | 0 |
| viltrum | A | template | write | 6.0K of 6.0K | 0.11 | 0.18-0.19 | 0 |
| viltrum | B | serialize | entries | 6.0K of 6.0K | 0.19-0.20 | 5.41-6.38 | 0 |
| viltrum | B | serialize | patch | 2.4K of 2.4K | 0.12 | 5.21-6.11 | 0 |
| viltrum | B | serialize | projects | 3.6K of 3.6K | 0.14 | 5.29-6.18 | 0 |
| viltrum | B | serialize | session | 6.0K of 6.0K | 0.13-0.14 | 5.25-6.28 | 0 |
| viltrum | B | serialize | timer | 6.0K of 6.0K | 0.10-0.11 | 5.10-6.03 | 0 |
| viltrum | B | template | entries | 6.0K of 6.0K | 0.11 | 9.64-12.8 | 0 |
| viltrum | B | template | patch | 2.4K of 2.4K | 0.10 | 9.08-12.8 | 0 |
| viltrum | B | template | projects | 3.6K of 3.6K | 0.10 | 9.12-12.9 | 0 |
| viltrum | B | template | session | 6.0K of 6.0K | 0.10 | 9.42-12.9 | 0 |
| viltrum | B | template | timer | 6.0K of 6.0K | 0.10 | 9.13-12.3 | 0 |
| viltrum | C | serialize | bookings | 133-151 of 153 | 23.0-210 | 507-5601 | 0 |
| viltrum | C | serialize | client | 50 of 51 | 4.29-19.0 | 881-2741 | 0 |
| viltrum | C | serialize | encounter | 191-202 of 204 | 9.04-11.2 | 745-3440 | 0 |
| viltrum | C | serialize | history | 196-202 of 204 | 6.33-19.9 | 746-3323 | 0 |
| viltrum | C | serialize | poll | 871-924 of 935 | 8.55-46.1 | 583-3360 | 0 |
| viltrum | C | serialize | shifts | 148-150 of 153 | 7.70-28.6 | 718-3100 | 0 |
| viltrum | C | template | bookings | 153 of 153 | 3.10-3.14 | 5.21-5.46 | 0 |
| viltrum | C | template | client | 51 of 51 | 0.10-0.11 | 1.80-2.07 | 0 |
| viltrum | C | template | encounter | 204 of 204 | 0.12-0.13 | 2.56-2.96 | 0 |
| viltrum | C | template | history | 204 of 204 | 0.13 | 3.02-3.32 | 0 |
| viltrum | C | template | poll | 934 of 935 | 0.11 | 2.94-3.07 | 0 |
| viltrum | C | template | shifts | 153 of 153 | 0.19 | 2.47-4.07 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| viltrum | A | serialize | 26.4-27.2 |  |
| viltrum | A | template | 22.5-23.1 |  |
| viltrum | B | serialize | 66.0-66.9 |  |
| viltrum | B | template | 34.2-34.8 |  |
| viltrum | C | serialize | 1639.9-1796.4 |  |
| viltrum | C | template | 330.0-334.7 |  |

