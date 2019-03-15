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

%global checksum        cf754ed01cb46df9d3fa4ac6f8bd2079

Name:           servicemesh-proxy
Version:        0.9.0
Release:        1%{?dist}
Summary:        The Istio Proxy is a microservice proxy that can be used on the client and server side, and forms a microservice mesh. The Proxy supports a large number of features.
License:        ASL 2.0
URL:            https://%{provider_prefix}

#Common
BuildRequires:  bazel = 0.22.0
BuildRequires:  ninja-build
BuildRequires:  devtoolset-4-gcc
BuildRequires:  devtoolset-4-gcc-c++
BuildRequires:  devtoolset-4-libatomic-devel
BuildRequires:  devtoolset-4-libstdc++-devel
BuildRequires:  devtoolset-4-runtime
BuildRequires:  libtool
BuildRequires:  go-toolset-1.11-golang
BuildRequires:  go-toolset-1.11-runtime
BuildRequires:  automake
BuildRequires:  autoconf
BuildRequires:  m4
BuildRequires:  perl
BuildRequires:  binutils

%if 0%{?centos} >= 7
BuildRequires:  cmake3
%else
BuildRequires:  llvm-toolset-7-cmake
BuildRequires:  llvm-toolset-7-runtime
BuildRequires:  llvm-toolset-7-cmake-data
%endif

Source0:        servicemesh-proxy.%{checksum}.tar.xz
Source1:        build.sh
Source2:        test.sh
Source3:        fetch.sh
Source4:        common.sh
Source5:        generate-servicemesh-source.sh

%description
The Istio Proxy is a microservice proxy that can be used on the client and server side, and forms a microservice mesh. The Proxy supports a large number of features.

########### servicemesh-proxy ###############
%package servicemesh-proxy
Summary:  The istio envoy proxy

%description servicemesh-proxy
The Istio Proxy is a microservice proxy that can be used on the client and server side, and forms a microservice mesh. The Proxy supports a large number of features.

This package contains the envoy program.

servicemesh-proxy is the proxy required by the Istio Pilot Agent that talks to Istio pilot

%prep
%setup -q -n %{name}

%build

%if 0%{?centos} >= 7
  export CENTOS=true
%endif

cd ..
source /opt/rh/go-toolset-1.11/enable
FETCH_DIR= CREATE_ARTIFACTS= STRIP=--strip-all %{SOURCE1}

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p ${RPM_BUILD_ROOT}/usr/local/bin

cp -pav ${RPM_BUILD_DIR}/envoy ${RPM_BUILD_ROOT}/usr/local/bin

%check
cd ..
RUN_TESTS=true %{SOURCE2}

%files
/usr/local/bin/envoy

%changelog
* Mon Mar 04 2019 Dmitri Dolguikh <ddolguik@redhat.com>
  Release 0.9.0-1
* Tue Feb 19 2019 Kevin Conner <kconner@redhat.com>
  Release 0.8.0-2
* Thu Feb 14 2019 Kevin Conner <kconner@redhat.com>
  Release 0.8.0-1
* Sun Jan 20 2019 Kevin Conner <kconner@redhat.com>
  Release 0.7.0-1
* Thu Jan 3 2019 Kevin Conner <kconner@redhat.com>
  Release 0.6.0-1 under servicemesh
* Mon Dec 31 2018 Kevin Conner <kconner@redhat.com>
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
