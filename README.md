# Nomad-NFS-Volume
Getting NFS up and running inside of Nomad was a bit of a challenge.

There just isn't a lot of documentation about mounting an NFS volume in Nomad,
and what I did find was already out of date because Nomad seems to be evolving
at a rapid pace.

The quick overview of what's needed:
1. an already functioning NFS server
1. a CSI NFS contoller plugin
1. a CSI NFS node plugin
1. a volume definition
1. a job specification that uses the volume

## The controller and node plugins. 
Hashicorp has a great explanation of the different kinds of storage plugin models[^1]
[right here](https://developer.hashicorp.com/nomad/docs/concepts/plugins/csi), where they state:

>There are three types of CSI plugins. Controller Plugins communicate with the
storage provider's APIs. [...] Node Plugins do the work on each client node,
like creating mount points. Monolith Plugins are plugins that perform both the
controller and node roles in the same instance.

In the example I've done, I've used a CSI plug in that provides separate
controller and node plugins. It's [GitHub repository is here](https://github.com/kubernetes-csi/csi-driver-nfs).


Setting the controller and node plugins up is pretty straight forward. These
end up working like most other `Docker` driver job specifications. Per the
Nomad documentation "... Nomad exposes a Unix domain socket named *csi.sock*
inside each CSI plugin task, and communicates over the gRPC protocol expected
by the CSI specification," and you'll notice both controller and nod plugins
set the location of the "endpoint" to be a unix socket. Additionally these
are lightweight, only getting spurts of activity when a job specification
initially spins up, so the cpu and memory resources are **very** low. Finally,
while the controller plugin can be "centrally" located on one Nomad client,
the node plugin needs to be present on each client in your Nomad cluster
_might_ use the volume, thus the `type = "system"` designation gets it
automagically deployed to every node in your cluster.

Knowing all that, getting the controller and node plugins runing should easy.
Since I run nomad commands *to* my cluster *from* my workstation that isn't a
member of the cluster, I start off by telling the nomad binary where my nomad
server is:

`$ export NOMAD_ADDR=http://172.16.0.10:4646`


Then it's just a matter of running the jobspecs for the controller and node CSI
plugins:

```
$ nomad job run nfs-controller.nomad
 <... snippage ...>
    Deployed
    Task Group  Desired  Placed  Healthy  Unhealthy  Progress Deadline
    plugin      1        1       1        0          2022-12-27T20:42:26-06:00

$ nomad job run nfs-node.nomad
 <... snippage ...>
    Deployed
    Task Group  Desired  Placed  Healthy  Unhealthy  Progress Deadline
    plugin      1        1       1        0          2022-12-27T20:47:12-06:00
```

## The creating the volume

This where things diverge from the comforts of Nomad jobspec syntax, and we
dive into run-of-the-mill Hashicorp HCL syntax to define the volume.

Replace `storage.monkeycloud.net` in the **mariadb.volume** file with the FQDNS or
IP address of your NFS server. Likewise, change `/nas/applications/mariadb` to the
actual NFS share you want to use. The `mount_options` is essentially the
equivalent `/etc/fstab` entry.

`mount_flags = ["nolock,nfsvers=4,rw,noatime"]`:

- I've used `nolock` because I don't run statd. This option will keep locks
"local" to the container, which works fine for my needs. You can omit this if
you have statd running.
- `nfsvers=4` is one of the many ways to you specify that you want to use the
NFSv4 protocol. You leave it out if your NFS server only speaks NFSv4.
- `rw` instructs users of this volume to mount it read and write capable.
- `noatime` means we don't waste time communicating access time changes over
the network.

Beyond that, most documentation wants you to `create` the volume. In my
example, the volumne already exists on an *external* nfs server, so I don't
`create` the volume, I just `register` the volume, and then allocate it in a
job specification.

`$ nomad volume register mariadb.volume`

And you're done allocationg the volume to future usage.

## Using your nfs share in a job specification

Now you've got your plugins setup, the volume registered, time to use it in
a job specification. In my case, if you haven't caught on, I wanted a MariaDB
server running that saved all it's relevant data onto my nfs share. The
[linuxserver.io image](https://hub.docker.com/r/linuxserver/mariadb/#!) is perfect because they've configured MariaDB to house
the stateful date into the `/config` directory, which makes a for a great
mount point for our nfs volume[^2].

Things to point out in the **mariadb.nomad** job specification:

- the `volume` stanza under the `group` stanza. This is where you allocate a
usage of the volume that you registered. The `source` is the `id` of the volume
you registerd in the **mariadb.volume** specification.
- the `volume_mount` section (under the `task` stanza) is where you actually use
the allocated volume in one of your jobs.
- For the love of anything, change the `MYSQL_ROOT_PASSWORD = "password123456789"`
to something secure. This is the ~~mysql~~MariaDB super user password.

`$ nomad job run mariadb.nomad`

That command should get you a functioning MariaDB server that uses your NFS share.
You can validate it by getting a command line on your client docker container and
execute the `mount` command. You should see something like:

```
<... snippage ...>

`storage.monkeycloud.net:/nas/applications/mariadb on /config type nfs4 (rw,noatime,vers=4.0,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=172.17.0.2,local_lock=none,addr=172.16.0.100)`

<... snippage ...>
```

---

[^1]: One of the interesting things is that HashiCorp Nomad uses the Container
Storage Interface (CSI) specification for storage plugins,
[so there's a rich library of storage plugins available](https://kubernetes-csi.github.io/docs/drivers.html)
since Kubernetes (and Apache Mesos) also the CSI specification.

[^2]: If you end up using their stuff, maybe consider [donating to them](https://opencollective.com/linuxserver/donate?amount=20) to support their work.

