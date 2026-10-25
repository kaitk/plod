Requests per second, median (range of runs), and the server's CPU time per request.

### Tier F

| Server | root | id | json | Peak RSS |
|---|---:|---:|---:|---:|
| goose-uring-bare | 488.8K (487.3K-492.6K), 8.2 µs | 487.5K (486.1K-491.8K), 8.2 µs | 413.8K (407.5K-415.3K), 9.6 µs | 7 MB |
| goose-epoll-bare | 390.5K (387.1K-392.3K), 10.3 µs | 378.8K (377.4K-379.1K), 10.6 µs | 323.7K (319.9K-325.2K), 12.4 µs | 4 MB |
| goose-uring-plod | 488.0K (486.9K-489.7K), 8.2 µs | 472.3K (469.7K-476.4K), 8.4 µs | 408.7K (406.8K-410.8K), 9.8 µs | 7 MB |
| goose-epoll-plod | 380.7K (380.3K-383.2K), 10.5 µs | 374.6K (359.9K-375.3K), 10.7 µs | 323.7K (320.4K-327.2K), 12.4 µs | 4 MB |

### Tier R

| Server | routes | Peak RSS |
|---|---:|---:|
| goose-uring-plod | 312.6K (310.1K-312.6K), 12.8 µs | 7 MB |
| goose-epoll-plod | 254.0K (253.5K-257.0K), 15.8 µs | 4 MB |
| goose-uring-plod-gen | 453.9K (453.5K-459.0K), 8.8 µs | 7 MB |
| goose-epoll-plod-gen | 361.2K (360.8K-362.9K), 11.1 µs | 4 MB |

### Tier M, against tier A

| Server | a | m | Peak RSS |
|---|---:|---:|---:|
| goose-uring-plod | 570.0K (558.8K-570.1K), 7.0 µs | 498.2K (496.2K-504.6K), 8.0 µs | 10 MB |
| goose-epoll-plod | 409.5K (400.8K-414.2K), 9.8 µs | 359.4K (355.9K-359.6K), 11.1 µs | 8 MB |
