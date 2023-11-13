# pcluster-monitoring-dashboard



## Summary

AWS Parallel Cluster creates and manages dynamic HPC clusters by using the open source job scheduler SLURM. While it enables CloudWatch for system metrics and logs, it lacks a monitoring dashboard for the workload. The Parallel Cluster monitoring dashboard (https://github.com/aws-samples/aws-parallelcluster-monitoring) provides job scheduler insights as well as detailed monitoring metrics in the OS level. With these metrics, cluster users and administrators can better understand the HPC workload and performance.

However, the solution is not updated for the latest version of Parallel Cluster and open source packages used in solution. This pattern brings the following enhancements to the solution:

Support of Parallel Cluster v3

Refresh of the open source software in the solution, including Prometheus, Grafana, Prometheus SLURM exporter, NVIDIA dcgm-exporter for GPU monitoring, etc.

Number of used CPU cores and GPUs by SLURM jobs

Job monitoring dashboard

GPU node monitoring dashboard enhancements for node with 4 or 8 GPUs

The solution has been implemented and verified in a customer HPC environment.

All scripts in this pattern are for Ubuntu 20. Amazon Linux or CentOS will need some small changes in these scripts. It might also require some small modifications for other versions of Ubuntu.

Product versions: Ubuntu 20.04, ParallelCluster 3.x

## Components
This project is build with the following components:

* **Grafana** is an [open-source](https://github.com/grafana/grafana) platform for monitoring and observability. Grafana allows you to query, visualize, alert on and understand your metrics as well as create, explore, and share dashboards fostering a data driven culture. 
* **Prometheus** [open-source](https://github.com/prometheus/prometheus/) project for systems and service monitoring from the [Cloud Native Computing Foundation](https://cncf.io/). It collects metrics from configured targets at given intervals, evaluates rule expressions, displays the results, and can trigger alerts if some condition is observed to be true.  
* The **Prometheus Pushgateway** is on [open-source](https://github.com/prometheus/pushgateway/) tool that allows ephemeral and batch jobs to expose their metrics to Prometheus.
* **[Nginx](http://nginx.org/)** is an HTTP and reverse proxy server, a mail proxy server, and a generic TCP/UDP proxy server.
* **[Prometheus-Slurm-Exporter](https://github.com/vpenso/prometheus-slurm-exporter/)** is a Prometheus collector and exporter for metrics extracted from the [Slurm](https://slurm.schedmd.com/overview.html) resource scheduling system.
* **[Node_exporter](https://github.com/prometheus/node_exporter)** is a Prometheus exporter for hardware and OS metrics exposed by \*NIX kernels, written in Go with pluggable metric collectors.

Note: *while almost all components are under the Apache2 license, only **[Prometheus-Slurm-Exporter is licensed under GPLv3](https://github.com/vpenso/prometheus-slurm-exporter/blob/master/LICENSE)**, you need to be aware of it and accept the license terms before proceeding and installing this component.*


Link for the deployment steps: [https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/set-up-a-grafana-monitoring-dashboard-for-aws-parallelcluster.html](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/set-up-a-grafana-monitoring-dashboard-for-aws-parallelcluster.html)
