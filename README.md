# Yadigar DIY Hardware Wallet Guide

Yadigar is an improved version of Blockstream's Jade firmware—with Turkish language support and optimizations specifically for the TTGO T-Display hardware. This repository contains a DIY installation script written in **Ruby** that flashes the Yadigar firmware onto your TTGO T-Display.

## Hardware Required

- TTGO T-Display
- USB cable
- Computer running Linux

## Installation

1. Open your Terminal.
2. Copy and paste one of the commands below:

### One-Liner (direct execution)
```bash
ruby -e "$(curl -fsSL https://github.com/sukunetsiz/yadigar-diy/raw/master/flash_the_ttgo_tdisplay.rb)"

