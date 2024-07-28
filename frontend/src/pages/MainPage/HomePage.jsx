import React from 'react';
import { Swiper, SwiperSlide } from 'swiper/react';

import './MaintPage.scss';

const HomePage = () => {

  return (
    <React.Fragment>
      <Swiper
        /*onSwiper={(swiper) => setSwiperRef(swiper)}*/
        slidesPerView={1}
        direction={'vertical'}
        className="main-carousel"
        allowTouchMove={false}
      >
        <SwiperSlide className="main-slide">

          <div className="main-fakeCol" />

        

        </SwiperSlide>
      </Swiper>
    </React.Fragment>
  );
};

export default HomePage;
