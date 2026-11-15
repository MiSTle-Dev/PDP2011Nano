# PDP2011Nano

The **PDP-11** is Digital Equipment Corporation's 16-bit minicomputer, launched in 1970. It is one of the most influential minicomputers ever built; early Unix and the C language were developed on it.

PDP2011Nano is a PDP-11 FPGA core for Tang and MiSTle boards, derived from the [pdp2011](https://pdp2011.sytse.net) core. It adds features such as TN20k 32-bit DRAM support, a pipelined MMU and an alternative VT52 terminal console, which saves resources so the core fits on a Nano 20k FPGA board.

| Board      | FPGA       |Note|
| ---        |        -   |-|
| [Tang Nano 20k](https://wiki.sipeed.com/nano20k)     | [GW2AR](https://www.gowinsemi.com/en/product/detail/38/)  ||
| [Tang Primer 25K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html) | [GW5A-25](https://www.gowinsemi.com/en/product/detail/60/) | |
| [MiSTle-25k](https://github.com/MiSTle-Dev/Boards/tree/main/mistle_gw3a_20) |[GW5A-25](https://www.gowinsemi.com/en/product/detail/60/)||

This project relies on an MPU connected to the FPGA (onboard BL616 or an external one). See the [MiSTle-Dev wiki](https://github.com/MiSTle-Dev/.github/wiki) for details.  

<img src="./.assets/pdp2011nano.png" alt="image" width="80%" height="auto">  

## License

The original pdp2011 VHDL code is copyright © 2008–2025 [Sytse van Slooten](https://pdp2011.sytse.net). See [LICENSE](LICENSE) for the terms.

## Features

* Configurable as PDP-11/20, 11/34, 11/44, 11/45, 11/70 or 11/94
* Disk controllers for RK, RL and RH (RM/RP) disks
* Terminal interface for an HDMI screen and USB keyboard, configurable as a VT100 or VT105
* Alternative VT52 terminal build to save FPGA resources, allowing more parallel disks
* Support for a second terminal via serial interface (TN20k USB-C with M0SDock or PiPico)

## Limitations

Due to FPGA resource limitations, the TN20k currently supports only a single disk type (e.g. RK) with the default VT100 console. A VT52 build allows two disk types. GW5A boards support three types (RK, RL, RH).

## feature candidates

* VT52 terminal optimization
* OSD selection of alternative boot ROM
* Magnetic tape
* Paper tape
* TN20k support for the [MINC Modular Instrument Computer](https://en.wikipedia.org/wiki/MINC-11?action=edit&redlink=1)
* Networking via an FPGA companion WLAN/LAN modem
