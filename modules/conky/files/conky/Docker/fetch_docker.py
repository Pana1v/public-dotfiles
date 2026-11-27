#!/usr/bin/env python3
"""Docker/ROS snapshot for the conky Docker card (runs under conky-feeds.service).

Always prints something, so errors reach the card instead of leaving a stale
cache. Output, tab-separated:
  E<TAB>message                              docker unusable (card shows it)
  S<TAB>running<TAB>total<TAB>domain<TAB>rmw one per snapshot
  C<TAB>name<TAB>image<TAB>uptime<TAB>cpu<TAB>mem   one per running container
Self-check: fetch_docker.py --selftest
"""

import json
import os
import re
import subprocess
import sys

DOCKER_TIMEOUT_SECONDS = 20
ROS_VARS = ("ROS_DOMAIN_ID", "RMW_IMPLEMENTATION")
UNSET = "-"
UP_UNITS = {"second": "s", "minute": "m", "hour": "h", "day": "d", "week": "w", "month": "mo", "year": "y"}


class DockerError(Exception):
    pass


def docker(*args):
    try:
        r = subprocess.run(["docker", *args], capture_output=True, text=True,
                           timeout=DOCKER_TIMEOUT_SECONDS, check=False)
    except FileNotFoundError:
        raise DockerError("docker not installed")
    except subprocess.TimeoutExpired:
        raise DockerError("docker not responding")
    if r.returncode == 0:
        return r.stdout
    err = r.stderr.lower()
    if "permission denied" in err:
        raise DockerError("no access, add user to docker group")
    if "cannot connect" in err or "no such file" in err or "is the docker daemon" in err:
        raise DockerError("daemon not running")
    raise DockerError("docker error")


def short_image(image):
    """registry/org/name:tag -> name:tag; digests dropped."""
    return image.split("@")[0].rsplit("/", 1)[-1]


def short_uptime(status):
    """'Up 13 hours (healthy)' -> '13h'; 'Up About an hour' -> '1h'."""
    m = re.match(r"Up\s+(?:(\d+)|About an?|Less than an?)\s+(\w+?)s?\b", status)
    if not m:
        return "-"
    return f"{m.group(1) or 1}{UP_UNITS.get(m.group(2), '')}"


def ros_env(env_lists, host_env):
    """Unique ROS values across containers, else the host's, else UNSET."""
    out = []
    for var in ROS_VARS:
        vals = []
        for env in env_lists:
            for item in env:
                k, _, v = item.partition("=")
                if k == var and v and v not in vals:
                    vals.append(v)
        if not vals and host_env.get(var):
            vals = [host_env[var]]
        out.append(",".join(vals) or UNSET)
    return out


def snapshot():
    ps = [line.split("\t") for line in docker("ps", "-a", "--format",
          "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.State}}\t{{.Status}}").splitlines() if line]
    running = [p for p in ps if p[3] == "running"]
    lines = []
    env_lists = []
    stats = {}
    if running:
        ids = [p[0] for p in running]
        for line in docker("stats", "--no-stream", "--format",
                           "{{.ID}}\t{{.CPUPerc}}\t{{.MemUsage}}", *ids).splitlines():
            f = line.split("\t")
            if len(f) == 3:
                stats[f[0]] = (f[1], f[2].split("/")[0].strip())
        env_lists = [c["Config"].get("Env") or [] for c in json.loads(docker("inspect", *ids))]
    domain, rmw = ros_env(env_lists, os.environ)
    lines.append(f"S\t{len(running)}\t{len(ps)}\t{domain}\t{rmw}")
    for p in running:
        cpu, mem = stats.get(p[0], ("-", "-"))
        lines.append(f"C\t{p[1]}\t{short_image(p[2])}\t{short_uptime(p[4])}\t{cpu}\t{mem}")
    return "\n".join(lines) + "\n"


def selftest():
    assert short_image("nvcr.io/nvidia/isaac/ros:x86_64-ros2_humble_abc") == "ros:x86_64-ros2_humble_abc"
    assert short_image("a/b@sha256:ff") == "b"
    assert short_uptime("Up 13 hours") == "13h"
    assert short_uptime("Up About an hour (healthy)") == "1h"
    assert short_uptime("Up 2 days") == "2d"
    assert short_uptime("Up Less than a second") == "1s"
    assert short_uptime("Exited (0) 3 hours ago") == "-"
    assert ros_env([["ROS_DOMAIN_ID=7", "X=1"], ["ROS_DOMAIN_ID=7"]], {}) == ["7", UNSET]
    assert ros_env([], {"RMW_IMPLEMENTATION": "rmw_cyclonedds_cpp"}) == [UNSET, "rmw_cyclonedds_cpp"]
    print("ok")


def main():
    if "--selftest" in sys.argv:
        selftest()
        return
    try:
        sys.stdout.write(snapshot())
    except DockerError as e:
        sys.stdout.write(f"E\t{e}\n")


if __name__ == "__main__":
    main()
