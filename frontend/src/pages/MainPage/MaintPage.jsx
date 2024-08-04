import React from 'react';
import { Swiper, SwiperSlide } from 'swiper/react';

import { Summary } from '../../components/Summary';
import { Mint } from '../../components/Mint';

import './MaintPage.scss';

const MaintPage = () => {
  return (
    <React.Fragment>
      <Swiper
        slidesPerView={1}
        direction={'vertical'}
        className="main-carousel"
        allowTouchMove={false}
      >
        <SwiperSlide className="main-slide">
          <div className="main-side">
            <Summary />
          </div>
          <div className="main-content">
            <div className="main-mintContainer">
              <Mint />
            </div>
          </div>
          <div className="main-fakeCol" />
        </SwiperSlide>
      </Swiper>
    </React.Fragment>
  );
};

export default MaintPage;
