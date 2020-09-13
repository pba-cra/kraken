describe('Transition all', () => {
  it('001', done => {
    const container1 = document.createElement('div');
    document.body.appendChild(container1);
    setElementStyle(container1, {
      position: 'absolute',
      top: '100px',
      left: 0,
      padding: '20px',
      backgroundColor: '#999',
      transition: 'all 1s ease-out',
    });
    container1.appendChild(document.createTextNode('DIV 1'));

    requestAnimationFrame(() => {
      setElementStyle(container1, {
        top: 0,
      });

      // Wait for animation finished.
      setTimeout(async () => {
        await matchViewportSnapshot();
        done();
      }, 1100);
    });
  });

  it('transition change height auto', async (done) => {
    let container = createElement('div', {
      style: {
        width: '100px',
        background: 'red',
        transition: 'height 2s ease'
      }
    }, [
      createText('1234')
    ]);
    BODY.appendChild(container);
    await matchViewportSnapshot();
    requestAnimationFrame(async () => {
      container.style.height = '50px';
      await matchViewportSnapshot();
      done();
    });
  });

  it('transition change width auto', async (done) => {
    let container = createElement('div', {
      style: {
        background: 'red',
        transition: 'width 2s ease'
      }
    }, [
      createText('1234')
    ]);
    BODY.appendChild(container);
    await matchViewportSnapshot();
    requestAnimationFrame(async () => {
      container.style.width = '100px';
      await matchViewportSnapshot();
      done();
    });
  });

  it('transition change top auto', async (done) => {
    let container = createElement('div', {
      style: {
        background: 'red',
        position: 'absolute',
        transition: 'top 2s ease'
      }
    }, [
      createText('1234')
    ]);
    BODY.appendChild(container);
    await matchViewportSnapshot();
    requestAnimationFrame(async () => {
      container.style.top = '100px';
      await matchViewportSnapshot();
      done();
    });
  });

  it('transition change left auto', async (done) => {
    let container = createElement('div', {
      style: {
        background: 'red',
        position: 'absolute',
        transition: 'left 2s ease'
      }
    }, [
      createText('1234')
    ]);
    BODY.appendChild(container);
    await matchViewportSnapshot();
    requestAnimationFrame(async () => {
      container.style.left = '100px';
      await matchViewportSnapshot();
      done();
    });
  });

  it('transition change right auto', async (done) => {
    let container = createElement('div', {
      style: {
        background: 'red',
        position: 'absolute',
        transition: 'right 2s ease'
      }
    }, [
      createText('1234')
    ]);
    BODY.appendChild(container);
    await matchViewportSnapshot();
    requestAnimationFrame(async () => {
      container.style.right = '100px';
      await matchViewportSnapshot();
      done();
    });
  });

  it('transition change bottom auto', async (done) => {
    let container = createElement('div', {
      style: {
        background: 'red',
        position: 'absolute',
        transition: 'bottom 2s ease'
      }
    }, [
      createText('1234')
    ]);
    BODY.appendChild(container);
    await matchViewportSnapshot();
    requestAnimationFrame(async () => {
      container.style.bottom = '100px';
      await matchViewportSnapshot();
      done();
    });
  });
});
