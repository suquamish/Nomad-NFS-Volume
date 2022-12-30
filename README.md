# Nomad-NFS-Volume
Getting NFS up and running inside of Nomad was a bit of a challenge.

There just isn't a lot of documentation about mounting an NFS volume in Nomad,
and what I did find was already out of date because Nomad seems to be evolving
at a rapid pace.

The quick overview of what's needed:
1. a functioning NFS server
1. an existing Nomad cluster
1. a CSI NFS plugin
1. a volume definition
1. a job specification that uses the volume


## Assumptions
First, I assume that you're using some linux distribution, but for me, all my
**clients** and **servers** are Debian Bullseye (at the time of writing) with
Nomad installed using the official HashiCorp repository.

Second, the way I describe some of the configuration changes need to get this
example running is impacted because of the distro I chose, and the Nomad
installation method I used. If you're here to learn how to get NFS to work with
Nomad on *your* cluster, my assumption is that you can handle any translation
between configuration styles of my installation and yours.

Third, I assume you're not just copy-n'-pasting these config files, and you
understand that things like server names, datacenter names, and NFS export
locations need to be changed to match your specific environment.

My fourth assumption is that you have a pretty good understanding how navigate
Linux and Docker. You understand things like filesystem mount options, and how
to get to the command line of a Docker container.

## The controller and node plugins.
The CSI plugins are the foundation of your cluster being able to use NFS
resources. Take a look at the `nfs-controller.nomad` and `nfs-node.nomad`
job specifications for this section.

Hashicorp has a great explanation of the different kinds of storage plugin
models[^1] [right here](https://developer.hashicorp.com/nomad/docs/concepts/plugins/csi),
where they state:

>There are three types of CSI plugins. Controller Plugins communicate with the
storage provider's APIs. [...] Node Plugins do the work on each client node,
like creating mount points. Monolith Plugins are plugins that perform both the
controller and node roles in the same instance.

In my example the CSI plug-in[^3] provides **controller** and **node** roles
separately, although there's one binary used for both roles. The role the
job takes on is setup in the `csi_plugin` stanza using the `type` parameter.
You need to use the same value for the `id` parameter in the `csi_plugin`
stanza for both so that Nomad knows they belong to the same plugin.

Setting the **controller** and **node** plugins up is pretty straight forward
for the job specification, with one noteworthy exeception; the **node** plugin
uses a `privileged = true` parameter in the `config` block. This parameter
gives the container access to the hosts devices, which means that Nomad and
Docker need to be configured to allow privileged containers. For me, this
required the following Nomad configuration change for all my **agents**, along
with a restart of Nomad:

```
$ cat /etc/nomad.d/docker.hcl
plugin "docker" {
  config {
    allow_privileged = true
  }
}
```

Per the Nomad documentation

>... Nomad exposes a Unix domain socket named *csi.sock* inside each CSI plugin
task, and communicates over the gRPC protocol expected by the CSI specification,

You'll notice both **controller** and **node** plugins set the location of the
"endpoint" to be a unix socket within' the `config` block's `args` parameter.
This places the unix socket the plugin listens/writes to at the same location
where Nomad will communicate over the exposed socket; that is the `mount_dir`
specified in the `csi_plugin` stanza. The `mount_dir` location will map to
local storage on your **agent**, specifically within the `data_dir` location of
your Nomad **agent** configuration.

These are lightweight jobs, only getting spurts of activity when a job
specification initially spins up, so the `cpu` and `memory` parameters can be
set low.

Finally, while the **controller** plugin can be "centrally" located on one Nomad
**agent**, the **node** plugin needs to be present on each **client** in your
Nomad cluster that *might* use the volume. Thus the `type = "system"` designation
gets it automagically deployed to every **client** in your cluster.

### Deploying
Since I run `nomad` commands *to* my cluster *from* my workstation that isn't
(strictly) an **agent** in the cluster, I start off by telling the `nomad`
binary where my Nomad **server** is:

`$ export NOMAD_ADDR=http://172.16.0.10:4646`


Then it's just a matter of running the jobspecs for the **controller** and
**node** CSI plugins:

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

## Creating the Volume

This where things diverge from the comforts of Nomad jobspec syntax, and we
dive into run-of-the-mill Hashicorp HCL syntax to define the volume. For this
section you'll be using the `mariadb.volume` file.

HashiCorp's [documentation on the Volume specification](https://developer.hashicorp.com/nomad/docs/other-specifications/volume)
is invaluable, but I'll go through some quick explanation of the settings.

The `plugin_id` tells your volume which plugin to register itself with.

The `context` block is going to to tell your CSI plugins where the NFS
resource is. The `server` parameter is the FQDNS or IP address of your NFS
server. Likewise the `share` parameter is the specific export that you want
this volume to use.

The `mount_options` block is essentially the equivalent of `/etc/fstab` where
you not only specify the `fs_type` but the mount options via the `mount_flags`
parameter.

You can specify more than one `capability` block to fill all the capabilities
your volume needs to provide. In my example, the volume must satify both the
`single-node-writer` and `single-node-reader-only` roles.

### Deploying
`$ nomad volume register mariadb.volume`

And you're done allocationg the volume to future usage. `volume register` just
sets up the volume to be used. Since the NFS volume already exists, it doesn't
need to be created, and allocating the volume in a jobspec will put it into
use.

## Using your NFS Volume in a job specification

Now you've got your plugins setup, the volume registered, time to use it in
a job specification. In my case, if you haven't caught on, I wanted a MariaDB
server running that saved all it's relevant data onto my NFS export. The
`mariadb.nomad` file is relevant to this section.

The [linuxserver.io image](https://hub.docker.com/r/linuxserver/mariadb/#!) is
perfect because they've configured MariaDB to house the stateful data into the
`/config` directory. This makes it a great mount point for our NFS volume[^2].

Points of interest in the job specification:

- the `volume` stanza under the `group` stanza is where you allocate a usage of
the Volume that you registered. The `source` parameter is the value of the `id`
parameter from `mariadb.volume`.
- the `volume_mount` stanza (under the `task` stanza) is where you actually use
the allocated Volume by mounting it in the container. The `volume` parameter is
the name of the `volume` stanza (☝️).

### Deploying
`$ nomad job run mariadb.nomad`

That command should get you a functioning MariaDB server that uses your NFS share.
You can validate it by getting a command line on your client Docker container and
executing the `mount` command; you should see something like:

```
<... snippage ...>

`storage.monkeycloud.net:/nas/applications/mariadb on /config type nfs4 (rw,noatime,vers=4.0,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=172.17.0.2,local_lock=none,addr=172.16.0.100)`

<... snippage ...>
```

---

[^1]: One of the interesting things is that HashiCorp Nomad uses the Container
Storage Interface (CSI) specification for storage plugins,
[so there's a rich library of storage plugins available](https://kubernetes-csi.github.io/docs/drivers.html)
since Kubernetes (and Apache Mesos) also use the CSI specification.

[^2]: If you end up using their stuff, maybe consider [donating to them](https://opencollective.com/linuxserver/donate?amount=20) to support their work.

[^3]: The CSI plugin's GitHub repository [is here](https://github.com/kubernetes-csi/csi-driver-nfs).
