import React from "react";
import Hero from "./components/Hero";
import Features from "./components/Features";
import HowItWorks from "./components/HowItWorks";
import Cta from "./components/Cta";
import Footer from "./components/Footer";
import "./FrontPage.scss";

const FrontPage: React.FC = () => (
  <div className="fp">
    <Hero />
    <Features />
    <HowItWorks />
    <Cta />
    <Footer />
  </div>
);

export default FrontPage;
