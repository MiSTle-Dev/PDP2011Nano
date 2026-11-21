# PDP2011Nano

The [**PDP-11**](https://en.wikipedia.org/wiki/PDP-11) is Digital Equipment Corporation's 16-bit minicomputer, launched in 1970. It is one of the most influential minicomputers ever built; early Unix and the C language were developed on it.

PDP2011Nano is a PDP-11 FPGA core for Tang and MiSTle boards, derived from the [pdp2011](https://pdp2011.sytse.net) core. It adds features such as TN20k 32-bit DRAM support, a pipelined MMU, modified disk controllers and sdcard interface apart from a hardwired [VT52](https://en.wikipedia.org/wiki/VT52) terminal console, which saves resources so the core fits on a Nano 20k FPGA board.

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
* [VT52](https://en.wikipedia.org/wiki/VT52) Terminal interface for an HDMI screen and USB keyboard
* Support for a second terminal via serial interface (TN20k USB-C with M0SDock or PiPico)

## Limitations

* Because of FPGA resource limits there is support for VT52 terminal only. VT100/105 terminal is not available

## status progress

* Disk boot from RK, RL and RH controller  
* So far no checks with a diagnostic program like xxdp done  
* many modifications had been needed to fit TN20k  

## feature candidates

* OSD selection of alternative boot ROM
* Magnetic tape
* Paper tape
* TN20k support for the [MINC Modular Instrument Computer](https://en.wikipedia.org/wiki/MINC-11?action=edit&redlink=1)
* Networking via an FPGA companion WLAN/LAN modem
