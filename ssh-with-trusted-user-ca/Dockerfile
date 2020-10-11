FROM ubuntu:18.04

ENV NOTVISIBLE "in users profile"

RUN apt-get update && \
    apt-get install --no-install-recommends --no-install-recommends -qq -y openssh-server curl jq && \
    mkdir /var/run/sshd && \
    echo "export VISIBLE=now" >> /etc/profile  && \
    sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

RUN adduser --disabled-password admin-ssh-user && \
    mkdir /home/admin-ssh-user/.ssh

RUN mkdir /ssh
COPY run.sh /ssh
COPY sshd_config /ssh

RUN chown -R admin-ssh-user /home/admin-ssh-user/.ssh  

EXPOSE 22

CMD ["/ssh/run.sh"]
