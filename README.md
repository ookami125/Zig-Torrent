<!-- Improved compatibility of back to top link: See: https://github.com/ookami125/Zig-Torrent/pull/73 -->
<a name="readme-top"></a>
<!--
*** Thanks for checking out the Best-README-Template. If you have a suggestion
*** that would make this better, please fork the repo and create a pull request
*** or simply open an issue with the tag "enhancement".
*** Don't forget to give the project a star!
*** Thanks again! Now go create something AMAZING! :D
-->



<!-- PROJECT SHIELDS -->
<!--
*** I'm using markdown "reference style" links for readability.
*** Reference links are enclosed in brackets [ ] instead of parentheses ( ).
*** See the bottom of this document for the declaration of the reference variables
*** for contributors-url, forks-url, etc. This is an optional, concise syntax you may use.
*** https://www.markdownguide.org/basic-syntax/#reference-style-links
-->
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![GNU GPLv3 License][license-shield]][license-url]



<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/ookami125/Zig-Torrent">
    <img src="images/logo.png" alt="Logo" width="80" height="80">
  </a>

  <h3 align="center">Zig Torrent Client</h3>

  <p align="center">
    An multi-file torrent client using an event and coroutine system
    <br />
    <a href="https://github.com/ookami125/Zig-Torrent"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/ookami125/Zig-Torrent">View Demo</a>
    ·
    <a href="https://github.com/ookami125/Zig-Torrent/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    ·
    <a href="https://github.com/ookami125/Zig-Torrent/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About The Project

<!-- [![Product Name Screen Shot][product-screenshot]](https://example.com) -->

The main goal of this project is to remove a lot of small projects I've made like an RSS file downloaded and an media sorter. This client's goal is to remove those while holding to some other standards.

* All torrent files should work
* Allow moving of media without breaking the connection
* Automate pulling of new content based on plugins
* Http client so client is headless by default but works on any device

Use the `GETTING_STARTED.md` to get started.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

All that should be needed is a
```sh
zig build -Doptimize=ReleaseFast run
```
If that doesn't work 

### Prerequisites

* Currently only supports linux
* zig version
	```sh
	$ zig version
	0.12.0-dev.2058+04ac028a2
	```

### Installation

_Below is an example of how you can instruct your audience on installing and setting up your app. This template doesn't rely on any external dependencies or services._

1. Clone the repo
   ```sh
   git clone https://github.com/ookami125/Zig-Torrent.git
   ```
2. Build with zig
   ```sh
   zig build -Doptimize=ReleaseFast
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

- [ ] Add Changelog
- [ ] Support DHT and other ways of getting torrent info
- [ ] Support multiple ways of changing a torrent (move files, delete, sparce download)

See the [open issues](https://github.com/ookami125/Zig-Torrent/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

Any contributions you make are **greatly appreciated**, but under my full discretion as how and when the change gets in.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->
## License

Distributed under the GNU GPLv3 License. See `LICENSE.txt` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTACT -->
## Contact

Tyler Peterson - TylerLGPeterson@gmail.com

Project Link: [https://github.com/ookami125/Zig-Torrent](https://github.com/ookami125/Zig-Torrent)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/cieric/Zig-Torrent.svg?style=for-the-badge
[contributors-url]: https://github.com/ookami125/Zig-Torrent/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/ookami125/Zig-Torrent.svg?style=for-the-badge
[forks-url]: https://github.com/ookami125/Zig-Torrent/network/members
[stars-shield]: https://img.shields.io/github/stars/ookami125/Zig-Torrent.svg?style=for-the-badge
[stars-url]: https://github.com/ookami125/Zig-Torrent/stargazers
[issues-shield]: https://img.shields.io/github/issues/ookami125/Zig-Torrent.svg?style=for-the-badge
[issues-url]: https://github.com/ookami125/Zig-Torrent/issues
[license-shield]: https://img.shields.io/github/license/ookami125/Zig-Torrent.svg?style=for-the-badge
[license-url]: https://github.com/ookami125/Zig-Torrent/blob/master/LICENSE.txt