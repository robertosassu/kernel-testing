#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# ima-evm-utils tests bash functions
#
# Copyright (C) 2020 Vitaly Chikunov <vt@altlinux.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# Tests accounting
declare -i testspass=0 testsfail=0 testsskip=0

# Exit codes (compatible with automake)
declare -r OK=0
declare -r FAIL=1
declare -r HARDFAIL=99 # hard failure no matter testing mode
declare -r SKIP=77

# You can set env VERBOSE=1 to see more output from evmctl
VERBOSE=${VERBOSE:-0}
V=vvvv
V=${V:0:$VERBOSE}
V=${V:+-$V}

# Exit if env FAILEARLY is defined.
# Used in expect_{pass,fail}.
exit_early() {
  if [ "$FAILEARLY" ]; then
    exit "$1"
  fi
}

# Require particular executables to be present
_require() {
  ret=
  for i; do
    if ! type $i; then
      echo "$i is required for test"
      ret=1
    fi
  done
  [ $ret ] && exit "$HARDFAIL"
}

# Non-TTY output is never colored
if [ -t 1 ]; then
     RED=$'\e[1;31m'
   GREEN=$'\e[1;32m'
  YELLOW=$'\e[1;33m'
    BLUE=$'\e[1;34m'
    CYAN=$'\e[1;36m'
    NORM=$'\e[m'
  export RED GREEN YELLOW BLUE CYAN NORM
fi

# Test mode determined by TFAIL variable:
#   undefined: to success testing
#   defined: failure testing
TFAIL=
TMODE=+ # mode character to prepend running command in log
declare -i TNESTED=0 # just for sanity checking

# Run positive test (one that should pass) and account its result
expect_pass() {
  local -i ret

  if [ -n "$TST_LIST" ] && [ "${TST_LIST/$1/}" = "$TST_LIST" ]; then
    [ "$VERBOSE" -gt 1 ] && echo "____ SKIP test: $*"
    testsskip+=1
    return "$SKIP"
  fi

  if [ $TNESTED -gt 0 ]; then
    echo $RED"expect_pass should not be run nested"$NORM
    testsfail+=1
    exit "$HARDFAIL"
  fi
  TFAIL=
  TMODE=+
  TNESTED+=1
  [ "$VERBOSE" -gt 1 ] && echo "____ START positive test: $*"
  "$@"
  ret=$?
  [ "$VERBOSE" -gt 1 ] && echo "^^^^ STOP ($ret) positive test: $*"
  TNESTED+=-1
  case $ret in
    0)  testspass+=1 ;;
    77) testsskip+=1 ;;
    99) testsfail+=1; exit_early 1 ;;
    *)  testsfail+=1; exit_early 2 ;;
  esac
  return $ret
}

expect_pass_if() {
  local indexes="$1"
  local ret

  shift

  expect_pass "$@"
  ret=$?

  if [ $ret -ne 0 ] && [ $ret -ne 77 ] && [ -n "$PATCHES" ]; then
    echo $YELLOW"Possibly missing patches:"$NORM
    for idx in $indexes; do
      echo $YELLOW" - ${PATCHES[$((idx))]}"$NORM
    done
  fi

  return $ret
}

# Eval negative test (one that should fail) and account its result
expect_fail() {
  local ret
  if [ -n "$TST_LIST" ] && [ "${TST_LIST/$1/}" = "$TST_LIST" ]; then
    [ "$VERBOSE" -gt 1 ] && echo "____ SKIP test: $*"
    testsskip+=1
    return "$SKIP"
  fi

  if [ $TNESTED -gt 0 ]; then
    echo $RED"expect_fail should not be run nested"$NORM
    testsfail+=1
    exit "$HARDFAIL"
  fi

  TFAIL=yes
  TMODE=-
  TNESTED+=1
  [ "$VERBOSE" -gt 1 ] && echo "____ START negative test: $*"
  "$@"
  ret=$?
  [ "$VERBOSE" -gt 1 ] && echo "^^^^ STOP ($ret) negative test: $*"
  TNESTED+=-1
  case $ret in
    0)  testsfail+=1; exit_early 3 ;;
    77) testsskip+=1 ;;
    99) testsfail+=1; exit_early 4 ;;
    *)  testspass+=1 ;;
  esac
  # Restore defaults (as in positive tests)
  # for tests to run without wrappers
  TFAIL=
  TMODE=+
  return $ret
}

expect_fail_if() {
  local indexes="$1"
  local ret

  shift

  expect_fail "$@"
  ret=$?

  if { [ $ret -eq 0 ] || [ $ret -eq 99 ]; } && [ -n "$PATCHES" ]; then
    echo $YELLOW"Possibly missing patches:"$NORM
    for idx in $indexes; do
      echo $YELLOW" - ${PATCHES[$((idx))]}"$NORM
    done
  fi

  return $ret
}

# return true if current test is positive
_test_expected_to_pass() {
  [ ! $TFAIL ]
}

# return true if current test is negative
_test_expected_to_fail() {
  [ $TFAIL ]
}

# Show blank line and color following text to red
# if it's real error (ie we are in expect_pass mode).
color_red_on_failure() {
  if _test_expected_to_pass; then
    echo "$RED"
    COLOR_RESTORE=true
  fi
}

# For hard errors
color_red() {
  echo "$RED"
  COLOR_RESTORE=true
}

color_restore() {
  [ $COLOR_RESTORE ] && echo "$NORM"
  COLOR_RESTORE=
}

# Show test stats and exit into automake test system
# with proper exit code (same as ours). Do cleanups.
_report_exit_and_cleanup() {
  local exit_code=$?

  if [ -n "${WORKDIR}" ]; then
    rm -rf "${WORKDIR}"
  fi

  "$@"

  if [ $testsfail -gt 0 ]; then
    echo "================================="
    echo " Run with FAILEARLY=1 $0 $*"
    echo " To stop after first failure"
    echo "================================="
  fi
  [ $testspass -gt 0 ] && echo -n "$GREEN" || echo -n "$NORM"
  echo -n "PASS: $testspass"
  [ $testsskip -gt 0 ] && echo -n "$YELLOW" || echo -n "$NORM"
  echo -n " SKIP: $testsskip"
  [ $testsfail -gt 0 ] && echo -n "$RED" || echo -n "$NORM"
  echo " FAIL: $testsfail"
  echo "$NORM"
  # Signal failure to the testing environment creator with an unclean shutdown.
  if [ -n "$TST_ENV" ] && [ $$ -eq 1 ]; then
    if [ -z "$(command -v poweroff)" ]; then
      echo "Warning: cannot properly shutdown system"
    fi

    # If no test was executed and the script was successful,
    # do a clean shutdown.
    if [ $testsfail -eq 0 ] && [ $testspass -eq 0 ] && [ $testsskip -eq 0 ] &&
       [ $exit_code -ne "$FAIL" ] && [ $exit_code -ne "$HARDFAIL" ]; then
      poweroff -f
    fi

    # If tests were executed and no test failed, do a clean shutdown.
    if { [ $testspass -gt 0 ] || [ $testsskip -gt 0 ]; } &&
       [ $testsfail -eq 0 ]; then
      poweroff -f
    fi
  fi
  if [ $testsfail -gt 0 ]; then
    exit "$FAIL"
  elif [ $testspass -gt 0 ]; then
    exit "$OK"
  elif [ $testsskip -gt 0 ]; then
    exit "$SKIP"
  else
    exit "$exit_code"
  fi
}

# Syntax: _run_env <kernel> <init> <additional kernel parameters>
_run_env() {
  if [ -z "$TST_ENV" ]; then
    return
  fi

  if [ $$ -eq 1 ]; then
    return
  fi

  if [ "$TST_ENV" = "um" ]; then
    expect_pass "$1" rootfstype=hostfs rw init="$2" quiet mem=2048M "$3"
  else
    echo $RED"Testing environment $TST_ENV not supported"$NORM
    exit "$FAIL"
  fi
}

# Syntax: _exit_env <kernel>
_exit_env() {
  if [ -z "$TST_ENV" ]; then
    return
  fi

  if [ $$ -eq 1 ]; then
    return
  fi

  exit "$OK"
}

# Syntax: _init_env
_init_env() {
  if [ -z "$TST_ENV" ]; then
    return
  fi

  if [ $$ -ne 1 ]; then
    return
  fi

  mount -t tmpfs tmpfs /tmp
  mount -t proc proc /proc
  mount -t sysfs sysfs /sys
  mount -t securityfs securityfs /sys/kernel/security

  if [ -n "$(command -v haveged 2> /dev/null)" ]; then
    $(command -v haveged) -w 1024 &> /dev/null
  fi

  pushd "$PWD" > /dev/null || exit "$FAIL"
}

# Syntax: _cleanup_env <cleanup function>
_cleanup_env() {
  if [ -z "$TST_ENV" ]; then
    $1
    return
  fi

  if [ $$ -ne 1 ]; then
    return
  fi

  $1

  umount /sys/kernel/security
  umount /sys
  umount /proc
  umount /tmp
}
