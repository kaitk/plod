## Saturation

| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| goose-uring | A | serialize | 579.0K | 573.4K-579.3K | 0.39 | 0.68 | 6.9 | 10 | 0 |
| goose-epoll | A | serialize | 422.1K | 409.7K-423.9K | 0.58 | 0.93 | 9.5 | 8 | 0 |
| goose-epoll-plod | A | serialize | 408.3K | 400.7K-409.8K | 0.62 | 0.95 | 9.8 | 8 | 0 |
| goose-uring-plod | A | serialize | 567.3K | 561.7K-569.6K | 0.40 | 0.68 | 7.0 | 10 | 0 |
| goose-uring | A | template | 581.4K | 572.8K-587.4K | 0.38 | 0.62 | 6.8 | 9 | 0 |
| goose-epoll | A | template | 424.8K | 424.0K-430.9K | 0.60 | 0.85 | 9.4 | 8 | 0 |
| goose-epoll-plod | A | template | 419.8K | 419.4K-430.2K | 0.60 | 0.88 | 9.5 | 8 | 0 |
| goose-uring-plod | A | template | 576.4K | 575.5K-579.2K | 0.39 | 0.64 | 6.9 | 9 | 0 |
| goose-uring | B | serialize | 298.4K | 298.3K-300.5K | 0.84 | 1.26 | 13.4 | 30 | 0 |
| goose-epoll | B | serialize | 232.3K | 232.0K-232.6K | 1.13 | 1.44 | 17.3 | 29 | 0 |
| goose-epoll-plod | B | serialize | 234.2K | 234.0K-235.1K | 1.11 | 1.51 | 17.1 | 29 | 0 |
| goose-uring-plod | B | serialize | 300.7K | 299.4K-301.6K | 0.84 | 1.23 | 13.3 | 31 | 0 |
| goose-uring | B | template | 380.0K | 376.3K-382.1K | 0.65 | 0.96 | 10.5 | 50 | 0 |
| goose-epoll | B | template | 284.8K | 280.9K-285.6K | 0.93 | 1.22 | 14.1 | 50 | 0 |
| goose-epoll-plod | B | template | 281.5K | 279.2K-288.8K | 0.91 | 1.39 | 14.2 | 50 | 0 |
| goose-uring-plod | B | template | 379.6K | 374.3K-379.8K | 0.66 | 0.97 | 10.5 | 50 | 0 |
| goose-uring | C | serialize | 60.5K | 59.6K-60.6K | 4.07 | 9.44 | 66.0 | 71 | 0 |
| goose-epoll | C | serialize | 59.2K | 58.7K-59.7K | 4.14 | 9.01 | 67.8 | 69 | 0 |
| goose-epoll-plod | C | serialize | 59.0K | 55.4K-59.6K | 4.17 | 8.84 | 68.0 | 69 | 0 |
| goose-uring-plod | C | serialize | 59.4K | 59.2K-60.1K | 4.14 | 9.70 | 67.2 | 71 | 0 |
| goose-uring | C | template | 147.2K | 146.2K-148.6K | 1.65 | 3.23 | 27.0 | 58 | 0 |
| goose-epoll | C | template | 138.8K | 137.7K-139.1K | 1.78 | 3.07 | 28.8 | 58 | 0 |
| goose-epoll-plod | C | template | 136.4K | 134.3K-137.0K | 1.82 | 3.10 | 29.3 | 58 | 0 |
| goose-uring-plod | C | template | 145.1K | 144.7K-145.2K | 1.69 | 3.26 | 27.4 | 58 | 0 |

## Tier D

| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |
|---|---|---:|---:|---:|---:|---:|---:|
| goose-uring | alone | 1.1K | 16.2-17.3 |  |  | 71 | 0 |
| goose-epoll | alone | 1.1K-1.2K | 15.2-17.3 |  |  | 69 | 0 |
| goose-epoll-plod | alone | 1.1K | 15.9-17.1 |  |  | 69 | 0 |
| goose-uring-plod | alone | 1.1K | 17.1-18.5 |  |  | 71 | 0 |
| goose-uring | beside forms | 175-179 | 116-137 | 7.0K-7.1K | 87.0-93.5 | 99 | 0 |
| goose-epoll | beside forms | 117-118 | 177-199 | 7.5K-7.6K | 103-105 | 132 | 0 |
| goose-epoll-plod | beside forms | 108-115 | 198-256 | 7.1K-7.3K | 106-114 | 149 | 0 |
| goose-uring-plod | beside forms | 163-169 | 125-140 | 6.7K | 89.8-91.6 | 109 | 0 |

## Fixed rate

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | A | serialize | item | 77.8K-77.9K of 78.0K | 0.10 | 0.16-0.44 | 0 |
| goose-uring | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16-0.28 | 0 |
| goose-uring | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.16-0.27 | 0 |
| goose-epoll | A | serialize | item | 77.7K-77.8K of 78.0K | 0.09-0.10 | 0.16-0.18 | 0 |
| goose-epoll | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.16-0.17 | 0 |
| goose-epoll | A | serialize | write | 6.0K of 6.0K | 0.10-0.11 | 0.16-0.17 | 0 |
| goose-epoll-plod | A | serialize | item | 77.7K-77.8K of 78.0K | 0.10 | 0.16 | 0 |
| goose-epoll-plod | A | serialize | me | 16.0K of 16.0K | 0.09 | 0.15-0.16 | 0 |
| goose-epoll-plod | A | serialize | write | 6.0K of 6.0K | 0.10-0.11 | 0.16-0.17 | 0 |
| goose-uring-plod | A | serialize | item | 77.8K of 78.0K | 0.10 | 0.16-0.21 | 0 |
| goose-uring-plod | A | serialize | me | 16.0K of 16.0K | 0.09-0.10 | 0.15-0.20 | 0 |
| goose-uring-plod | A | serialize | write | 6.0K of 6.0K | 0.11 | 0.16-0.19 | 0 |
| goose-uring | A | template | item | 77.8K-77.9K of 78.0K | 0.10 | 0.15-0.16 | 0 |
| goose-uring | A | template | me | 16.0K of 16.0K | 0.09 | 0.15 | 0 |
| goose-uring | A | template | write | 6.0K of 6.0K | 0.11 | 0.16 | 0 |
| goose-epoll | A | template | item | 77.7K-77.8K of 78.0K | 0.09-0.10 | 0.16-0.18 | 0 |
| goose-epoll | A | template | me | 16.0K of 16.0K | 0.09 | 0.16-0.17 | 0 |
| goose-epoll | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-0.18 | 0 |
| goose-epoll-plod | A | template | item | 77.8K of 78.0K | 0.10 | 0.16 | 0 |
| goose-epoll-plod | A | template | me | 16.0K of 16.0K | 0.09 | 0.16 | 0 |
| goose-epoll-plod | A | template | write | 6.0K of 6.0K | 0.11 | 0.16-0.17 | 0 |
| goose-uring-plod | A | template | item | 77.8K-77.9K of 78.0K | 0.10 | 0.16-0.17 | 0 |
| goose-uring-plod | A | template | me | 16.0K of 16.0K | 0.09 | 0.15-0.16 | 0 |
| goose-uring-plod | A | template | write | 6.0K of 6.0K | 0.11 | 0.16 | 0 |
| goose-uring | B | serialize | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-uring | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-uring | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-uring | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-uring | B | serialize | timer | 6.0K of 6.0K | 0.09-0.10 | 0.13-0.14 | 0 |
| goose-epoll | B | serialize | entries | 6.0K of 6.0K | 0.10 | 0.14-0.16 | 0 |
| goose-epoll | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-epoll | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-epoll | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.13-0.14 | 0 |
| goose-epoll | B | serialize | timer | 6.0K of 6.0K | 0.09 | 0.13-0.15 | 0 |
| goose-epoll-plod | B | serialize | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll-plod | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-epoll-plod | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-epoll-plod | B | serialize | session | 6.0K of 6.0K | 0.09-0.10 | 0.13-0.14 | 0 |
| goose-epoll-plod | B | serialize | timer | 6.0K of 6.0K | 0.09 | 0.13-0.14 | 0 |
| goose-uring-plod | B | serialize | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-uring-plod | B | serialize | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-uring-plod | B | serialize | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-uring-plod | B | serialize | session | 6.0K of 6.0K | 0.10 | 0.13-0.14 | 0 |
| goose-uring-plod | B | serialize | timer | 6.0K of 6.0K | 0.09-0.10 | 0.13-0.14 | 0 |
| goose-uring | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-uring | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-uring | B | template | projects | 3.6K of 3.6K | 0.10 | 0.14 | 0 |
| goose-uring | B | template | session | 6.0K of 6.0K | 0.09-0.10 | 0.13-0.14 | 0 |
| goose-uring | B | template | timer | 6.0K of 6.0K | 0.09 | 0.13-0.14 | 0 |
| goose-epoll | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll | B | template | patch | 2.4K of 2.4K | 0.10 | 0.13-0.15 | 0 |
| goose-epoll | B | template | projects | 3.6K of 3.6K | 0.10 | 0.13-0.14 | 0 |
| goose-epoll | B | template | session | 6.0K of 6.0K | 0.09 | 0.13-0.14 | 0 |
| goose-epoll | B | template | timer | 6.0K of 6.0K | 0.09 | 0.13-0.14 | 0 |
| goose-epoll-plod | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14-0.15 | 0 |
| goose-epoll-plod | B | template | patch | 2.4K of 2.4K | 0.10 | 0.13-0.14 | 0 |
| goose-epoll-plod | B | template | projects | 3.6K of 3.6K | 0.10 | 0.13-0.14 | 0 |
| goose-epoll-plod | B | template | session | 6.0K of 6.0K | 0.09-0.10 | 0.13-0.15 | 0 |
| goose-epoll-plod | B | template | timer | 6.0K of 6.0K | 0.09-0.10 | 0.13-0.15 | 0 |
| goose-uring-plod | B | template | entries | 6.0K of 6.0K | 0.10 | 0.14 | 0 |
| goose-uring-plod | B | template | patch | 2.4K of 2.4K | 0.10 | 0.14 | 0 |
| goose-uring-plod | B | template | projects | 3.6K of 3.6K | 0.10 | 0.13-0.14 | 0 |
| goose-uring-plod | B | template | session | 6.0K of 6.0K | 0.09-0.10 | 0.13-0.14 | 0 |
| goose-uring-plod | B | template | timer | 6.0K of 6.0K | 0.09-0.10 | 0.13-0.14 | 0 |
| goose-uring | C | serialize | bookings | 153 of 153 | 0.66-0.70 | 0.83-0.87 | 0 |
| goose-uring | C | serialize | client | 51 of 51 | 0.11-0.12 | 0.15-0.65 | 0 |
| goose-uring | C | serialize | encounter | 204 of 204 | 0.12 | 0.16-0.34 | 0 |
| goose-uring | C | serialize | history | 204 of 204 | 0.14 | 0.19-0.60 | 0 |
| goose-uring | C | serialize | poll | 933-935 of 935 | 0.10 | 0.44-0.48 | 0 |
| goose-uring | C | serialize | shifts | 153 of 153 | 0.11-0.12 | 0.15-0.17 | 0 |
| goose-epoll | C | serialize | bookings | 153 of 153 | 0.69-0.70 | 0.81-0.84 | 0 |
| goose-epoll | C | serialize | client | 51 of 51 | 0.11 | 0.15-0.67 | 0 |
| goose-epoll | C | serialize | encounter | 204 of 204 | 0.12 | 0.16-0.17 | 0 |
| goose-epoll | C | serialize | history | 204 of 204 | 0.14 | 0.18-0.48 | 0 |
| goose-epoll | C | serialize | poll | 933-934 of 935 | 0.10 | 0.45-0.51 | 0 |
| goose-epoll | C | serialize | shifts | 153 of 153 | 0.11 | 0.15-0.17 | 0 |
| goose-epoll-plod | C | serialize | bookings | 153 of 153 | 0.66-0.70 | 0.82-0.89 | 0 |
| goose-epoll-plod | C | serialize | client | 51 of 51 | 0.10-0.11 | 0.14-0.56 | 0 |
| goose-epoll-plod | C | serialize | encounter | 204 of 204 | 0.12 | 0.16-0.17 | 0 |
| goose-epoll-plod | C | serialize | history | 204 of 204 | 0.14 | 0.37-0.68 | 0 |
| goose-epoll-plod | C | serialize | poll | 934 of 935 | 0.10 | 0.49 | 0 |
| goose-epoll-plod | C | serialize | shifts | 153 of 153 | 0.11-0.12 | 0.15-0.19 | 0 |
| goose-uring-plod | C | serialize | bookings | 153 of 153 | 0.67-0.68 | 0.83-0.86 | 0 |
| goose-uring-plod | C | serialize | client | 51 of 51 | 0.10-0.12 | 0.15-0.65 | 0 |
| goose-uring-plod | C | serialize | encounter | 204 of 204 | 0.12 | 0.17-0.24 | 0 |
| goose-uring-plod | C | serialize | history | 204 of 204 | 0.14-0.15 | 0.19-0.57 | 0 |
| goose-uring-plod | C | serialize | poll | 934 of 935 | 0.10 | 0.43-0.47 | 0 |
| goose-uring-plod | C | serialize | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.18 | 0 |
| goose-uring | C | template | bookings | 153 of 153 | 0.27-0.28 | 0.38-0.51 | 0 |
| goose-uring | C | template | client | 51 of 51 | 0.10-0.11 | 0.14-0.15 | 0 |
| goose-uring | C | template | encounter | 204 of 204 | 0.11-0.12 | 0.16-0.18 | 0 |
| goose-uring | C | template | history | 204 of 204 | 0.13 | 0.17-0.18 | 0 |
| goose-uring | C | template | poll | 934 of 935 | 0.10 | 0.16-0.18 | 0 |
| goose-uring | C | template | shifts | 153 of 153 | 0.11 | 0.15-0.16 | 0 |
| goose-epoll | C | template | bookings | 153 of 153 | 0.28 | 0.40-0.41 | 0 |
| goose-epoll | C | template | client | 51 of 51 | 0.11 | 0.15-0.26 | 0 |
| goose-epoll | C | template | encounter | 204 of 204 | 0.11-0.12 | 0.15-0.16 | 0 |
| goose-epoll | C | template | history | 204 of 204 | 0.13 | 0.18-0.27 | 0 |
| goose-epoll | C | template | poll | 933-934 of 935 | 0.10 | 0.16 | 0 |
| goose-epoll | C | template | shifts | 153 of 153 | 0.11 | 0.15 | 0 |
| goose-epoll-plod | C | template | bookings | 153 of 153 | 0.28 | 0.41-0.45 | 0 |
| goose-epoll-plod | C | template | client | 51 of 51 | 0.10-0.12 | 0.15-0.26 | 0 |
| goose-epoll-plod | C | template | encounter | 204 of 204 | 0.11-0.12 | 0.16-0.17 | 0 |
| goose-epoll-plod | C | template | history | 204 of 204 | 0.13 | 0.17-0.26 | 0 |
| goose-epoll-plod | C | template | poll | 933-934 of 935 | 0.10 | 0.15-0.19 | 0 |
| goose-epoll-plod | C | template | shifts | 153 of 153 | 0.11 | 0.15-0.16 | 0 |
| goose-uring-plod | C | template | bookings | 153 of 153 | 0.28 | 0.40-0.45 | 0 |
| goose-uring-plod | C | template | client | 51 of 51 | 0.11-0.12 | 0.15-0.29 | 0 |
| goose-uring-plod | C | template | encounter | 204 of 204 | 0.12 | 0.16-0.21 | 0 |
| goose-uring-plod | C | template | history | 204 of 204 | 0.12-0.13 | 0.17-0.20 | 0 |
| goose-uring-plod | C | template | poll | 933-935 of 935 | 0.10 | 0.16-0.19 | 0 |
| goose-uring-plod | C | template | shifts | 153 of 153 | 0.11 | 0.15-0.17 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | A | serialize | 21.3-21.5 |  |
| goose-epoll | A | serialize | 20.3-21.3 |  |
| goose-epoll-plod | A | serialize | 20.9-21.9 |  |
| goose-uring-plod | A | serialize | 20.6-21.6 |  |
| goose-uring | A | template | 20.9-21.2 |  |
| goose-epoll | A | template | 20.1-20.9 |  |
| goose-epoll-plod | A | template | 20.8-21.2 |  |
| goose-uring-plod | A | template | 20.7-21.0 |  |
| goose-uring | B | serialize | 31.8-32.2 |  |
| goose-epoll | B | serialize | 31.3-31.6 |  |
| goose-epoll-plod | B | serialize | 31.2-31.7 |  |
| goose-uring-plod | B | serialize | 31.9-32.0 |  |
| goose-uring | B | template | 30.3-30.7 |  |
| goose-epoll | B | template | 29.9-30.4 |  |
| goose-epoll-plod | B | template | 29.0-30.2 |  |
| goose-uring-plod | B | template | 30.7-31.2 |  |
| goose-uring | C | serialize | 87.9-90.3 |  |
| goose-epoll | C | serialize | 88.7-90.6 |  |
| goose-epoll-plod | C | serialize | 89.1-91.0 |  |
| goose-uring-plod | C | serialize | 89.4-90.6 |  |
| goose-uring | C | template | 51.0-52.2 |  |
| goose-epoll | C | template | 50.3-50.6 |  |
| goose-epoll-plod | C | template | 51.0-52.2 |  |
| goose-uring-plod | C | template | 51.8-53.3 |  |

## Mixed run: tier C's reads, alone and beside uploads

| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |
|---|---|---|---|---:|---:|---:|---:|
| goose-uring | C | alone | bookings | 153 of 153 | 0.69 | 0.82-0.84 | 0 |
| goose-uring | C | alone | client | 51 of 51 | 0.10-0.12 | 0.13-0.69 | 0 |
| goose-uring | C | alone | encounter | 204 of 204 | 0.12 | 0.17 | 0 |
| goose-uring | C | alone | history | 204 of 204 | 0.14 | 0.18-0.72 | 0 |
| goose-uring | C | alone | poll | 933 of 935 | 0.10 | 0.48-0.49 | 0 |
| goose-uring | C | alone | shifts | 153 of 153 | 0.11-0.12 | 0.16-0.17 | 0 |
| goose-epoll | C | alone | bookings | 153 of 153 | 0.69-0.70 | 0.82-0.83 | 0 |
| goose-epoll | C | alone | client | 51 of 51 | 0.11 | 0.14-0.30 | 0 |
| goose-epoll | C | alone | encounter | 204 of 204 | 0.12 | 0.16 | 0 |
| goose-epoll | C | alone | history | 204 of 204 | 0.14 | 0.42-0.65 | 0 |
| goose-epoll | C | alone | poll | 934 of 935 | 0.10 | 0.45-0.47 | 0 |
| goose-epoll | C | alone | shifts | 153 of 153 | 0.12 | 0.15-0.17 | 0 |
| goose-epoll-plod | C | alone | bookings | 153 of 153 | 0.69-0.70 | 0.82-0.84 | 0 |
| goose-epoll-plod | C | alone | client | 51 of 51 | 0.11-0.12 | 0.15-0.73 | 0 |
| goose-epoll-plod | C | alone | encounter | 204 of 204 | 0.12 | 0.16-0.17 | 0 |
| goose-epoll-plod | C | alone | history | 204 of 204 | 0.14 | 0.67-0.70 | 0 |
| goose-epoll-plod | C | alone | poll | 933-934 of 935 | 0.10 | 0.46-0.49 | 0 |
| goose-epoll-plod | C | alone | shifts | 153 of 153 | 0.11-0.12 | 0.16 | 0 |
| goose-uring-plod | C | alone | bookings | 153 of 153 | 0.67-0.68 | 0.81-0.84 | 0 |
| goose-uring-plod | C | alone | client | 51 of 51 | 0.10-0.11 | 0.13-0.66 | 0 |
| goose-uring-plod | C | alone | encounter | 204 of 204 | 0.12 | 0.16-0.18 | 0 |
| goose-uring-plod | C | alone | history | 204 of 204 | 0.14 | 0.19-0.47 | 0 |
| goose-uring-plod | C | alone | poll | 933-934 of 935 | 0.10 | 0.41-0.45 | 0 |
| goose-uring-plod | C | alone | shifts | 153 of 153 | 0.12 | 0.16-0.17 | 0 |
| goose-uring | C | uploads | bookings | 153 of 153 | 2.99-3.73 | 8.30-9.76 | 0 |
| goose-uring | C | uploads | client | 51 of 51 | 2.87-3.71 | 8.43-9.54 | 0 |
| goose-uring | C | uploads | encounter | 204 of 204 | 2.77-3.63 | 8.26-9.56 | 0 |
| goose-uring | C | uploads | history | 204 of 204 | 2.82-2.98 | 8.18-8.75 | 0 |
| goose-uring | C | uploads | poll | 933 of 935 | 2.74-3.33 | 8.36-9.44 | 0 |
| goose-uring | C | uploads | shifts | 153 of 153 | 2.67-3.02 | 8.22-9.38 | 0 |
| goose-epoll | C | uploads | bookings | 153 of 153 | 0.77-0.80 | 1.31-1.44 | 0 |
| goose-epoll | C | uploads | client | 51 of 51 | 0.16-0.17 | 0.46-0.61 | 0 |
| goose-epoll | C | uploads | encounter | 204 of 204 | 0.18-0.24 | 0.59-0.92 | 0 |
| goose-epoll | C | uploads | history | 204 of 204 | 0.21-0.23 | 0.78-1.05 | 0 |
| goose-epoll | C | uploads | poll | 933-934 of 935 | 0.17-0.18 | 0.75-0.92 | 0 |
| goose-epoll | C | uploads | shifts | 153 of 153 | 0.18-0.23 | 0.52-0.65 | 0 |
| goose-epoll-plod | C | uploads | bookings | 153 of 153 | 0.78-0.81 | 1.37-1.41 | 0 |
| goose-epoll-plod | C | uploads | client | 51 of 51 | 0.16-0.22 | 0.53-0.57 | 0 |
| goose-epoll-plod | C | uploads | encounter | 204 of 204 | 0.18-0.21 | 0.59-0.99 | 0 |
| goose-epoll-plod | C | uploads | history | 204 of 204 | 0.23 | 0.86-1.03 | 0 |
| goose-epoll-plod | C | uploads | poll | 933-934 of 935 | 0.18-0.19 | 0.85-0.89 | 0 |
| goose-epoll-plod | C | uploads | shifts | 153 of 153 | 0.17-0.20 | 0.54-0.62 | 0 |
| goose-uring-plod | C | uploads | bookings | 153 of 153 | 3.09-3.44 | 8.59-10.3 | 0 |
| goose-uring-plod | C | uploads | client | 51 of 51 | 2.42-3.07 | 6.97-9.41 | 0 |
| goose-uring-plod | C | uploads | encounter | 204 of 204 | 2.89-3.51 | 8.43-10.6 | 0 |
| goose-uring-plod | C | uploads | history | 204 of 204 | 2.69-3.14 | 7.87-10.3 | 0 |
| goose-uring-plod | C | uploads | poll | 932-933 of 935 | 3.21-3.35 | 8.34-11.0 | 0 |
| goose-uring-plod | C | uploads | shifts | 153 of 153 | 2.89-3.33 | 7.83-10.6 | 0 |

| Server | Tier | Run | CPU µs/req | uploads/s |
|---|---|---|---:|---:|
| goose-uring | C | alone | 89.9-91.1 |  |
| goose-epoll | C | alone | 89.1-90.6 |  |
| goose-epoll-plod | C | alone | 89.1-90.3 |  |
| goose-uring-plod | C | alone | 89.5-89.9 |  |
| goose-uring | C | uploads | 2324.9-2348.4 | 1.0K-1.1K |
| goose-epoll | C | uploads | 2313.4-2342.4 | 1.0K-1.1K |
| goose-epoll-plod | C | uploads | 2335.0-2358.4 | 1.0K-1.1K |
| goose-uring-plod | C | uploads | 2301.8-2345.0 | 1.0K-1.1K |

