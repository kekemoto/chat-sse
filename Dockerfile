FROM centos:8

RUN dnf install -y git
RUN dnf install -y vim

# Install rbenv
RUN git clone https://github.com/rbenv/rbenv.git ~/.rbenv
RUN echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
RUN echo 'eval "$(rbenv init -)"' >> ~/.bashrc

# Install rbenv-build
RUN mkdir -p ~/.rbenv/plugins
RUN git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# Install Ruby
RUN dnf install -y bzip2 gcc openssl-devel readline-devel zlib-devel make
RUN ~/.rbenv/bin/rbenv install 2.7.1
RUN ~/.rbenv/bin/rbenv global 2.7.1

# bundle install
RUN mkdir /root/chat
WORKDIR /root/chat
RUN /root/.rbenv/shims/gem install bundle
COPY Gemfile .
COPY Gemfile.lock .
RUN /root/.rbenv/shims/bundle install

CMD /root/.rbenv/shims/bundle exec rerun "ruby server/app.rb -o 0.0.0.0 -p 80"
