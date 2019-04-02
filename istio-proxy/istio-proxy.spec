# Generate devel rpm
%global with_devel 0
# Build with debug info rpm
%global with_debug 0

%if 0%{?with_debug}
%global _dwz_low_mem_die_limit 0
%else
%global debug_package   %{nil}
%endif

%global git_commit f95f8530df5b6b71c163bf23c7bd2e2a3501382d 
%global git_shortcommit  %(c=%{git_commit}; echo ${c:0:7})

# https://github.com/istio/proxy
%global provider        github
%global provider_tld    com
%global project         istio
%global repo            proxy
%global provider_prefix %{provider}.%{provider_tld}/%{project}/%{repo}

Name:           istio-proxy
Version:        0.10.0
Release:        1%{?dist}
Summary:        The Istio Proxy is a microservice proxy that can be used on the client and server side, and forms a microservice mesh. The Proxy supports a large number of features.
License:        ASL 2.0
URL:            https://%{provider_prefix}

#Common
BuildRequires:  bazel = 0.22.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  patch
BuildRequires:  ksh
BuildRequires:  xz
BuildRequires:  golang
BuildRequires:  automake
BuildRequires:  python3
BuildRequires:  cmake3
BuildRequires:  openssl
BuildRequires:  openssl-devel

Source0:        proxy-full-%{version}.tar.xz
Source1:        build.sh
Source2:        test.sh
Source3:        fetch.sh
Source4:        common.sh
Source5:        bazel_get_workspace_status

%description
The Istio Proxy is a microservice proxy that can be used on the client and server side, and forms a microservice mesh. The Proxy supports a large number of features.

########### istio-proxy ###############
%package istio-proxy
Summary:  The istio envoy proxy

%description istio-proxy
The Istio Proxy is a microservice proxy that can be used on the client and server side, and forms a microservice mesh. The Proxy supports a large number of features.

This package contains the envoy program.

istio-proxy is the proxy required by the Istio Pilot Agent that talks to Istio pilot

%prep
%setup -q -n %{name}

%build

%if 0%{?centos} >= 7
  export CENTOS=true
%endif

cd ..
PROXY_NAME=istio-proxy FETCH_DIR= CREATE_ARTIFACTS= %{SOURCE1}

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p ${RPM_BUILD_ROOT}/usr/local/bin

cp -pav ${RPM_BUILD_DIR}/envoy ${RPM_BUILD_ROOT}/usr/local/bin

%check
cd ..
PROXY_NAME=istio-proxy RUN_TESTS=true %{SOURCE2}

%files
/usr/local/bin/envoy

%changelog
* Thu Mar 04 2019 Dmitri Dolguikh <ddolguik@redhat.com>
  Release 0.9.0-1
* Thu Feb 14 2019 Kevin Conner <kconner@redhat.com>
  Release 0.8.0-1
* Sun Jan 20 2019 Kevin Conner <kconner@redhat.com>
  Release 0.7.0-1
* Thu Dec 20 2018 Kevin Conner <kconner@redhat.com>
  Release 0.6.0-1
* Wed Nov 21 2018 Dmitri Dolguikh <ddolguik@redhat.com>
  Release 0.5.0-1
* Mon Oct 29 2018 Dmitri Dolguikh <ddolguik@redhat.com>
  Release 0.4.0-1
* Fri Oct 12 2018 Dmitri Dolguikh <ddolguik@redhat.com>
  Release 0.3.0-1
* Wed Sep 12 2018 Dmitri Dolguikh <ddolguik@redhat.com>
  Release 0.2.0-1
* Tue Jul 31 2018 Dmitri Dolguikh <ddolguik@redhat.com>
- Release 0.1.0-1
* Mon Mar 5 2018 Bill DeCoste <wdecoste@redhat.com>
- First package 
