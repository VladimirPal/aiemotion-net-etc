// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`).
// There are various equivalent ways to declare your Docusaurus config.
// See: https://docusaurus.io/docs/api/docusaurus-config

import { themes as prismThemes } from "prism-react-renderer";

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: "AIEmotion Internal Documentation",
  favicon: "img/favicon.ico",

  url: "https://docs.aiemotion.net",
  baseUrl: "/",

  organizationName: "aiemotion",
  projectName: "aiemotion-docs",

  onBrokenLinks: "warn",

  markdown: {
    hooks: {
      onBrokenMarkdownLinks: "warn",
      onBrokenMarkdownImages: "warn",
    },
  },

  i18n: {
    defaultLocale: "en",
    locales: ["en"],
  },

  presets: [
    [
      "classic",
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: "./sidebars.js",
          editUrl: "https://github.com/aiemotion/aiemotion-docs/tree/master/docusaurus",
        },
        theme: {
          customCss: "./src/css/custom.css",
        },
      }),
    ],
  ],

  plugins: [
    [
      "@docusaurus/plugin-content-blog",
      {
        id: "decisions",
        routeBasePath: "decisions",
        path: "../decisions",
        showReadingTime: true,
        blogTitle: "Architecture Decisions",
        blogDescription: "Architecture Decision Records (ADRs) for AIEmotion",
        blogSidebarTitle: "Recent Decisions",
        blogSidebarCount: 5,
        editUrl: "https://github.com/web-pal/apps-it-pal-net-etc/tree/master/docusaurus",
        feedOptions: {
          type: ["rss", "atom"],
          xslt: true,
        },
      },
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      // Replace with your project's social card
      image: "img/docusaurus-social-card.jpg",
      navbar: {
        title: "AIEmotion Docs",
        logo: {
          alt: "AIEmotion Logo",
          src: "img/logo.svg",
        },
        items: [
          {
            type: "docSidebar",
            sidebarId: "aiemotionDocsSidebar",
            position: "left",
            label: "Documentation",
          },
          {
            to: "/decisions",
            label: "Decisions",
            position: "left",
          },
          {
            href: "https://github.com/aiemotion/aiemotion-docs/tree/master/docusaurus",
            label: "GitHub",
            position: "right",
          },
        ],
      },
      footer: {
        style: "dark",
        links: [
          {
            title: "Documentation",
            items: [
              {
                label: "Documentation",
                to: "/docs",
              },
              {
                label: "Decisions",
                to: "/decisions",
              },
            ],
          },
          {
            title: "Community",
            items: [
              {
                label: "GitHub",
                href: "https://github.com/aiemotion/aiemotion-docs",
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} AIEmotion. Built with Docusaurus.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
      },
    }),
};

export default config;
